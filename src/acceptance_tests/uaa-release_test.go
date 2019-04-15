package acceptance_tests_test

import (
	"crypto/tls"
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
	"unicode"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/ginkgo/extensions/table"
	. "github.com/onsi/gomega"
	"github.com/onsi/gomega/gbytes"
	"github.com/onsi/gomega/gexec"
	"github.com/pavel-v-chernykh/keystore-go"
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

	AfterEach(func() {
		deleteUAA()
	})

	DescribeTable("uaa truststore", func(addedOSConfCertificates int, optFiles ...string) {
		deployUAA()
		numCertificatesBeforeDeploy := getNumOfOSCertificates()
		deployUAA(optFiles...)
		numCertificatesAfterDeploy := getNumOfOSCertificates()
		Expect(numCertificatesAfterDeploy).To(Equal(numCertificatesBeforeDeploy + addedOSConfCertificates))

		caCertificatesPemEncodedMap := buildCACertificatesPemEncodedMap()

		var trustStoreMap map[string]interface{}
		Eventually(func() map[string]interface{} {
			trustStoreMap = buildTruststoreMap()
			return trustStoreMap
		}, 5*time.Minute, 10*time.Second).Should(HaveLen(len(caCertificatesPemEncodedMap)))

		for key := range caCertificatesPemEncodedMap {
			Expect(trustStoreMap).To(HaveKey(key))
		}

	},
		Entry("with os-conf not adding certs", 0, "./opsfiles/os-conf-0-certificate.yml"),
		Entry("with os-conf + ca_cert property adding certificates", 11, "./opsfiles/os-conf-1-certificate.yml", "./opsfiles/load-more-ca-certs.yml"),
	)

	Context("UAA consuming the `database` link", func() {
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
				cmd := exec.Command(boshBinaryPath, "-d", "uaa", "stop", "-n", "database/0")
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
					}, time.Second*10).Should(Equal("200 "))
				})
			})
		})

	})

	DescribeTable("UAA log format", func(uaaLogFormat string, optFiles ...string) {
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
		Entry("when UAA logs are configured to *NOT* honor RFC 3339",
			`^\[(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2}\.\d{3})\] uaa.* - \d+ \[(.+)\] .... (DEBUG|\sINFO|\sWARN) --- .+: .+`),
		Entry("when UAA logs are configured to honor RFC 3339",
			`^\[(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2}\.\d{3})Z\] uaa.* - \d+ \[(.+)\] .... (DEBUG|\sINFO|\sWARN) --- .+: .+`,
			"./opsfiles/use-rfc3339-log-format.yml"),
	)
})

var _ = Describe("uaa-rotator-errand", func() {
	It("running the key-rotator errand should exit 0", func() {
		deployUAA()

		runErrandCmd := exec.Command(boshBinaryPath, "run-errand", "uaa_key_rotator")
		session, err := gexec.Start(runErrandCmd, GinkgoWriter, GinkgoWriter)
		Expect(err).NotTo(HaveOccurred())
		Eventually(session, 5*time.Minute).Should(gexec.Exit(0))
	})
})

var _ = Describe("setting a custom UAA port", func() {
	BeforeEach(func() {
		deployUAA("./opsfiles/non-default-localhost-http-port.yml", "./opsfiles/non-default-ssl-port.yml")
	})

	Context("with custom http and https port", func() {
		It("health_check should check the health on the correct port", func() {
			assertUAAIsHealthy("/var/vcap/jobs/uaa/bin/health_check")

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

func assertUAAIsHealthy(healthCheckPath string) {
	healthCheckCmd := exec.Command(boshBinaryPath, []string{"--json", "ssh", "--results", "uaa", "-c", healthCheckPath}...)
	session, err := gexec.Start(healthCheckCmd, GinkgoWriter, GinkgoWriter)
	Expect(err).NotTo(HaveOccurred())
	Eventually(session, 5*time.Minute).Should(gexec.Exit(0))
}

func buildTruststoreMap() map[string]interface{} {
	By("downloading the truststore")
	localKeyStorePath := scpTruststore()
	localKeyStoreFile, err := os.Open(localKeyStorePath)
	Expect(err).NotTo(HaveOccurred())
	keyStoreDecoded, err := keystore.Decode(localKeyStoreFile, []byte("changeit"))
	Expect(err).NotTo(HaveOccurred())

	trustStoreCertMap := map[string]interface{}{}
	for _, cert := range keyStoreDecoded {
		if trustedCertEntry, isCorrectType := cert.(*keystore.TrustedCertificateEntry); isCorrectType {
			block := &pem.Block{
				Type:  "CERTIFICATE",
				Bytes: trustedCertEntry.Certificate.Content,
			}
			trustStoreCertMap[string(pem.EncodeToMemory(block))] = nil
		}
	}

	return trustStoreCertMap
}

func buildCACertificatesPemEncodedMap() map[string]interface{} {
	By("downloading the os ssl ca certificates")
	caCertificatesPath := scpOSSSLCertFile()
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

func scpOSSSLCertFile() string {
	caCertificatesPath := filepath.Join(os.TempDir(), "ca-certificates.crt")
	cmd := exec.Command(boshBinaryPath, "scp", "uaa:/etc/ssl/certs/ca-certificates.crt", caCertificatesPath)
	session, err := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	Expect(err).NotTo(HaveOccurred())
	Eventually(session, 10*time.Second).Should(gexec.Exit(0))

	return caCertificatesPath
}

func scpTruststore() string {
	localKeyStorePath := filepath.Join(os.TempDir(), "cacerts")
	cmd := exec.Command(boshBinaryPath, "scp", "uaa:/var/vcap/data/uaa/cert-cache/cacerts", localKeyStorePath)
	session, err := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	Expect(err).NotTo(HaveOccurred())
	Eventually(session, 10*time.Second).Should(gexec.Exit(0))
	return localKeyStorePath
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

func getNumOfOSCertificates() int {
	caCertificatesSSHStdoutCmd := exec.Command(boshBinaryPath, []string{"--json", "ssh", "--results", "uaa", "-c", "sudo grep 'END CERTIFICATE' /etc/ssl/certs/ca-certificates.crt | wc -l"}...)
	session, err := gexec.Start(caCertificatesSSHStdoutCmd, GinkgoWriter, GinkgoWriter)
	Expect(err).NotTo(HaveOccurred())
	Eventually(session, 1*time.Minute).Should(gexec.Exit(0))

	var result = &sshResult{}
	err = json.Unmarshal(session.Out.Contents(), result)
	Expect(err).NotTo(HaveOccurred())
	Expect(result.Tables).To(HaveLen(1))
	Expect(result.Tables[0].Rows).To(HaveLen(1))

	numOfCerts, err := strconv.Atoi(
		strings.TrimFunc(string(result.Tables[0].Rows[0].Stdout), func(r rune) bool {
			return !unicode.IsNumber(r)
		}),
	)
	Expect(err).NotTo(HaveOccurred())
	Expect(numOfCerts).To(BeNumerically(">=", 148))
	return numOfCerts
}
