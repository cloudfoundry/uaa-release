package acceptance_tests_test

import (
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/ginkgo/extensions/table"
	. "github.com/onsi/gomega"
	"github.com/onsi/gomega/gbytes"
	"github.com/onsi/gomega/gexec"
)

type row struct {
	Stdout   string `json:"stdout"`
	ExitCode string `json:"exit_code"`
}

type table struct {
	Rows []row
}

type sshResult struct {
	Tables []table
}

var _ = Describe("UaaRelease", func() {
	It("populates the uaa truststore", func() {
		deployUAA()

		numberOfCertsInUaaDockerDeploymentYml := 2
		caCertificatesPemEncodedMap := buildCACertificatesPemEncodedMap()

		expectedNumberOfCerts := len(caCertificatesPemEncodedMap) + numberOfCertsInUaaDockerDeploymentYml

		countNumberOfCerts := runCommandOnUaaViaSsh("sudo /var/vcap/packages/uaa/jdk/bin/keytool -list -storepass 'changeit' -keystore /var/vcap/data/uaa/cert-cache/cacerts")
		Expect(countNumberOfCerts).To(ContainSubstring("Your keystore contains " + strconv.Itoa(expectedNumberOfCerts) + " entries"))

		uaaTrustStoreFingerprints := runCommandOnUaaViaSsh("sudo /var/vcap/packages/uaa/jdk/bin/keytool  -keystore /var/vcap/data/uaa/cert-cache/cacerts -storepass 'changeit' -list  | grep 'Certificate fingerprint'| cut -d ' ' -f 4 ")

		for certificate := range caCertificatesPemEncodedMap {
			fingerprint, err := getFingerPrint([]byte(certificate))
			Expect(err).NotTo(HaveOccurred())
			Expect(uaaTrustStoreFingerprints).To(ContainSubstring(fingerprint))
		}

		// Verify that said file is actually making it to the jvm as a truststore
		Eventually(verifyTomcatIsUsingCorrectTruststore(),
			5*time.Minute,
			10*time.Second).Should(BeTrue())
	})

	Context("hardens the on-disk truststore against symlink attacks", func() {
		BeforeEach(func() {
			deployUAA()
		})

		It("locks down cert-cache to 0711 root:root to prevent the vcap process from tampering with it", func() {
			statOutput := runCommandOnUaaViaSsh("sudo stat -c '%a %U:%G' /var/vcap/data/uaa/cert-cache")
			Expect(strings.TrimSpace(statOutput)).To(Equal("711 root:root"))
		})

		It("replaces a pre-planted symlink at cert-cache with a real directory on next pre-start", func() {
			// Threat model: an attacker with vcap-level access (a compromised
			// UAA process) plants a symlink at cert-cache before the next
			// pre-start runs. Without the defense in ensure_persistent_cert_dir_secure,
			// pre-start would run as root and follow the symlink, writing
			// keystore material into the attacker-chosen target.
			runCommandOnUaaViaSsh(strings.Join([]string{
				"sudo rm -rf /tmp/canary-dir",
				"sudo mkdir -p /tmp/canary-dir",
				"echo untouched | sudo tee /tmp/canary-dir/sentinel > /dev/null",
				"sudo rm -rf /var/vcap/data/uaa/cert-cache",
				"sudo ln -s /tmp/canary-dir /var/vcap/data/uaa/cert-cache",
				"sudo /var/vcap/jobs/uaa/bin/pre-start > /dev/null 2>&1",
			}, " && "))
			defer runCommandOnUaaViaSsh("sudo rm -rf /tmp/canary-dir")

			kind := runCommandOnUaaViaSsh("sudo test -L /var/vcap/data/uaa/cert-cache && echo LINK || echo DIR")
			Expect(strings.TrimSpace(kind)).To(Equal("DIR"))

			listing := runCommandOnUaaViaSsh("sudo ls /tmp/canary-dir")
			Expect(strings.TrimSpace(listing)).To(Equal("sentinel"))

			sentinel := runCommandOnUaaViaSsh("sudo cat /tmp/canary-dir/sentinel")
			Expect(strings.TrimSpace(sentinel)).To(Equal("untouched"))
		})

		It("does not follow vcap-planted symlinks for individual cache files on next pre-start", func() {
			// Threat model: vcap can write inside cert-cache (which is
			// 0700 vcap:vcap after configure_tomcat). An attacker replaces
			// one of the cache files with a symlink to a privileged path;
			// without the rm -f before cp in save_new_cache_files_to_persistent_disk,
			// pre-start's cp would follow the symlink and overwrite the
			// attacker-chosen target.
			runCommandOnUaaViaSsh(strings.Join([]string{
				"sudo rm -f /tmp/canary-file",
				"echo untouched | sudo tee /tmp/canary-file > /dev/null",
				"sudo ln -sf /tmp/canary-file /var/vcap/data/uaa/cert-cache/os-certs-cache.txt",
				"sudo /var/vcap/jobs/uaa/bin/pre-start > /dev/null 2>&1",
			}, " && "))
			defer runCommandOnUaaViaSsh("sudo rm -f /tmp/canary-file")

			canary := runCommandOnUaaViaSsh("sudo cat /tmp/canary-file")
			Expect(strings.TrimSpace(canary)).To(Equal("untouched"))

			kind := runCommandOnUaaViaSsh("sudo test -L /var/vcap/data/uaa/cert-cache/os-certs-cache.txt && echo LINK || echo FILE")
			Expect(strings.TrimSpace(kind)).To(Equal("FILE"))
		})
	})

	XContext("UAA consuming the `database` link", func() {
		var originalEtcHostsContents []byte

		BeforeEach(func() {
			etcHosts, err := os.OpenFile("/etc/hosts", os.O_RDWR|os.O_APPEND, os.ModePerm)
			Expect(err).NotTo(HaveOccurred())

			originalEtcHostsContents, err = ioutil.ReadAll(etcHosts)
			Expect(err).NotTo(HaveOccurred())
		})

		AfterEach(func() {
			Expect(ioutil.WriteFile("/etc/hosts", originalEtcHostsContents, os.ModePerm)).To(Succeed())
		})

		It("should connect to a healthy database instance", func() {
			deployUAA("./opsfiles/two-db-instances.yml", "./opsfiles/scale-down-db-instances.yml")

			transCfg := &http.Transport{
				TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
			}
			client := &http.Client{Transport: transCfg}

			uaaDomainName := "uaa.localhost"
			By("setting a local domain name: uaa.localhost to point to localhost", func() {
				addLocalDNS(uaaDomainName)
			})

			By("confirming that the UAA can find its database", func() {
				uaaHealthzEndpoint := fmt.Sprintf("https://%s:8443/healthz", uaaDomainName)
				By(fmt.Sprintf("calling /healthz endpoint %s should return health", uaaHealthzEndpoint), func() {
					healthzResp, err := client.Get(uaaHealthzEndpoint)
					Expect(err).NotTo(HaveOccurred())
					Expect(healthzResp.Status).To(Equal("200 "))
					Eventually(gbytes.BufferReader(healthzResp.Body)).Should(gbytes.Say("ok"))
				})

				uaaRootEndpoint := fmt.Sprintf("https://%s:8443/", uaaDomainName)
				By(fmt.Sprintf("calling root / endpoint %s should return 200", uaaRootEndpoint), func() {
					Eventually(func() string {
						rootUrl, err := client.Get(uaaRootEndpoint)
						Expect(err).NotTo(HaveOccurred())
						return rootUrl.Status
					}, time.Second*2).Should(Equal("200 "))
				})
			})

			deployUAA("./opsfiles/two-db-instances.yml")

			By("stopping the first DB instance", func() {
				cmd := exec.Command(boshBinaryPath, "-d", os.Getenv("BOSH_DEPLOYMENT"), "stop", "-n", "database/0")
				session, err := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
				Expect(err).NotTo(HaveOccurred())
				Eventually(session, 5*time.Minute).Should(gexec.Exit(0))
			})

			By("confirming that the UAA has not cached the database IP", func() {
				uaaHealthzEndpoint := fmt.Sprintf("https://%s:8443/healthz", uaaDomainName)
				By(fmt.Sprintf("calling /healthz endpoint %s should return health", uaaHealthzEndpoint), func() {
					healthzResp, err := client.Get(uaaHealthzEndpoint)
					Expect(err).NotTo(HaveOccurred())
					Expect(healthzResp.Status).To(Equal("200 "))
					Eventually(gbytes.BufferReader(healthzResp.Body)).Should(gbytes.Say("ok"))
				})

				uaaRootEndpoint := fmt.Sprintf("https://%s:8443/", uaaDomainName)
				By(fmt.Sprintf("calling root / endpoint %s should return 200", uaaRootEndpoint), func() {
					Eventually(func() string {
						rootUrl, err := client.Get(uaaRootEndpoint)
						Expect(err).NotTo(HaveOccurred())
						return rootUrl.Status
					}, 30*time.Second).Should(Equal("200 "))
				})
			})
		})

	})

	logLineWithoutTimestampRegex := ` uaa.* - \d+ \[([^]]+)\] - \[[^]]+\] .... (DEBUG|\sINFO|\sWARN) --- .+: .+`

	DescribeTable("UAA log format", func(
		uaaLogFormat string,
		optFiles ...string,
	) {
		deployUAA(optFiles...)

		logPath := scpUAALog()
		auditLogPath := scpUaaAuditLog()

		tailLogFileCmd := exec.Command("tail", "-n1", logPath)
		session, err := gexec.Start(tailLogFileCmd, GinkgoWriter, GinkgoWriter)
		Expect(err).NotTo(HaveOccurred())
		Expect(string(session.Wait().Out.Contents())).To(MatchRegexp(uaaLogFormat))

		tailAuditLogFileCmd := exec.Command("tail", "-n1", auditLogPath)
		session, err = gexec.Start(tailAuditLogFileCmd, GinkgoWriter, GinkgoWriter)
		Expect(err).NotTo(HaveOccurred())
		Expect(string(session.Wait().Out.Contents())).To(MatchRegexp(uaaLogFormat))
	},
		Entry("when UAA log format is not set and default value is used",
			`^\[(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2}\.\d{6,9})Z\]`+logLineWithoutTimestampRegex),
		Entry("when UAA logs are configured to rfc3339",
			`^\[(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2}\.\d{6,9})Z\]`+logLineWithoutTimestampRegex,
			"./opsfiles/configure-to-rfc3339-log-format.yml"),
		Entry("when UAA logs are configured to rfc3339-legacy",
			`^\[(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2}\.\d{3})Z\]`+logLineWithoutTimestampRegex,
			"./opsfiles/configure-to-rfc3339-legacy-log-format.yml"),
		Entry("when UAA logs are configured to deprecated",
			`^\[(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2}\.\d{3})\]`+logLineWithoutTimestampRegex,
			"./opsfiles/configure-to-deprecated-log-format.yml"),
	)
})

var _ = Describe("setting a custom UAA port", func() {
	BeforeEach(func() {
		deployUAA("./opsfiles/non-default-localhost-http-port.yml", "./opsfiles/non-default-ssl-port.yml")
	})

	Context("with custom http and https port", func() {
		It("health_check should check the health on the correct port", func() {
			assertUAAIsHealthy("/var/vcap/jobs/uaa/bin/health_check")

			By("GET / from within the VM should redirect to https using the configured https port", func() {
				curlResult := runCommandOnUaaViaSsh("curl -v localhost:9000")
				Expect(curlResult).To(ContainSubstring("HTTP/1.1 301"))
				Expect(curlResult).To(ContainSubstring("Location: https://localhost:9443/"))
			})

			transCfg := &http.Transport{
				TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
			}
			client := &http.Client{Transport: transCfg}

			uaaDomainName := "uaa.localhost"
			By("setting a local domain name: uaa.localhost to point to localhost", func() {
				addLocalDNS(uaaDomainName)
			})

			uaaHealthzEndpoint := fmt.Sprintf("https://%s:9443/healthz", uaaDomainName)
			By(fmt.Sprintf("calling /healthz endpoint %s should return health", uaaHealthzEndpoint), func() {
				healthzResp, err := client.Get(uaaHealthzEndpoint)
				Expect(err).NotTo(HaveOccurred())
				Expect(healthzResp.StatusCode).To(Equal(http.StatusOK))
				Eventually(gbytes.BufferReader(healthzResp.Body)).Should(gbytes.Say("ok"))
			})

			uaaHealthzEndpoint = fmt.Sprintf("http://%s:9443/healthz", uaaDomainName)
			By(fmt.Sprintf("calling /healthz endpoint %s should fail", uaaHealthzEndpoint), func() {
				healthzResp, err := client.Get(uaaHealthzEndpoint)
				Expect(err).NotTo(HaveOccurred())
				Expect(healthzResp.StatusCode).To(Equal(http.StatusBadRequest))
				Eventually(gbytes.BufferReader(healthzResp.Body)).Should(gbytes.Say(`Bad Request(\s)*This combination of host and port requires TLS.`))
			})
		})
	})
})

func runCommandOnUaaViaSsh(command string) string {
	sshCommand := exec.Command(boshBinaryPath, []string{"ssh", "uaa", "--json", "--results", "-c", command}...)
	session, err := gexec.Start(sshCommand, GinkgoWriter, GinkgoWriter)
	Expect(err).NotTo(HaveOccurred())
	Eventually(session, 5*time.Minute).Should(gexec.Exit(0))

	var result = &sshResult{}
	err = json.Unmarshal(session.Out.Contents(), result)
	Expect(err).NotTo(HaveOccurred())
	Expect(result.Tables).To(HaveLen(1))
	Expect(result.Tables[0].Rows).To(HaveLen(1))

	return string(result.Tables[0].Rows[0].Stdout)
}

func assertUAAIsHealthy(healthCheckPath string) {
	runCommandOnUaaViaSsh(healthCheckPath)
}

func verifyTomcatIsUsingCorrectTruststore() bool {
	tomcatProcessCmdOutput := runCommandOnUaaViaSsh("ps aux | grep -E 'tomcat|uaa-boot.war'")
	return strings.Contains(tomcatProcessCmdOutput, "-Djavax.net.ssl.trustStore=/var/vcap/data/uaa/cert-cache/cacerts")
}

func buildCACertificatesPemEncodedMap() map[string]interface{} {
	By("downloading the operating system ssl ca certificates")
	caCertificatesPath := scpSystemSSLCertFile()
	caCertificatesContent, err := ioutil.ReadFile(caCertificatesPath)
	Expect(err).NotTo(HaveOccurred())

	var caCertificatesPem *pem.Block
	var rest []byte

	caCertificates := map[string]interface{}{}

	for {
		caCertificatesPem, rest = pem.Decode(caCertificatesContent)

		if caCertificatesPem == nil {
			break
		}
		caCertificates[string(pem.EncodeToMemory(caCertificatesPem))] = nil
		caCertificatesContent = rest
	}

	return caCertificates
}

func scpSystemSSLCertFile() string {
	caCertificatesPath := filepath.Join(os.TempDir(), "uaa-ca-certificates.crt")
	cmd := exec.Command(boshBinaryPath, "scp", "uaa:/etc/ssl/certs/uaa-ca-certificates.crt", caCertificatesPath)
	session, err := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	Expect(err).NotTo(HaveOccurred())
	Eventually(session, 10*time.Second).Should(gexec.Exit(0))

	return caCertificatesPath
}

func scpUAALog() string {
	localUAALogPath := filepath.Join(os.TempDir(), "uaa.log")
	cmd := exec.Command(boshBinaryPath, "scp", "uaa:/var/vcap/sys/log/uaa/uaa.log", localUAALogPath)
	session, err := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	Expect(err).NotTo(HaveOccurred())
	Eventually(session, 10*time.Second).Should(gexec.Exit(0))
	return localUAALogPath
}

func scpUaaAuditLog() string {
	localUAALogPath := filepath.Join(os.TempDir(), "uaa_events.log")
	cmd := exec.Command(boshBinaryPath, "scp", "uaa:/var/vcap/sys/log/uaa/uaa_events.log", localUAALogPath)
	session, err := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	Expect(err).NotTo(HaveOccurred())
	Eventually(session, 10*time.Second).Should(gexec.Exit(0))
	return localUAALogPath
}

func getFingerPrint(certdata []byte) (
	string,
	error,
) {
	var block *pem.Block
	block, _ = pem.Decode(certdata)

	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return "", err
	}
	fingerprint := sha256.Sum256(cert.Raw)
	var hexfingerprint []string
	for _, b := range fingerprint {
		hexVal := strings.ToUpper(fmt.Sprintf("%02s", strconv.FormatUint(uint64(b), 16)))
		hexfingerprint = append(hexfingerprint, hexVal)
	}
	return strings.Join(hexfingerprint, ":"), nil

}
