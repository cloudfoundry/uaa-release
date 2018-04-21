package acceptance_tests_test

import (
	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"os/exec"
	"github.com/onsi/gomega/gexec"
	"time"
	"encoding/json"
	"strconv"
	"strings"
	"unicode"
	. "github.com/onsi/ginkgo/extensions/table"
	"github.com/pavel-v-chernykh/keystore-go"
	"os"
	"path/filepath"
	"encoding/pem"
	"io/ioutil"
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
		Entry("without BPM enabled", 0, "./opsfiles/disable-bpm.yml", "./opsfiles/os-conf-0-certificate.yml"),
		Entry("without BPM enabled and with os-conf adding a certificate", 1, "./opsfiles/disable-bpm.yml", "./opsfiles/os-conf-1-certificate.yml"),
		Entry("with BPM enabled", 0, "./opsfiles/enable-bpm.yml", "./opsfiles/os-conf-0-certificate.yml"),
		Entry("with BPM enabled and os-conf adding a certificate", 1, "./opsfiles/enable-bpm.yml", "./opsfiles/os-conf-1-certificate.yml"),
	)
})

var _ = Describe("setting a custom UAA port", func() {
	Describe("with bpm enabled", func() {
		It("health_check should check the health on the correct port", func() {
			deployUAA("./opsfiles/non-default-uaa-port.yml")

			healthCheckCmd := exec.Command(boshBinaryPath, []string{"--json", "ssh", "--results", "uaa", "-c", "/var/vcap/jobs/uaa/bin/health_check"}...)
			session, err := gexec.Start(healthCheckCmd, GinkgoWriter, GinkgoWriter)
			Expect(err).NotTo(HaveOccurred())
			Eventually(session, 5*time.Minute).Should(gexec.Exit(0))
		})
	})

	Describe("with bpm disabled", func() {
		It("health_check should check the health on the correct port", func() {
			deployUAA("./opsfiles/non-default-uaa-port.yml", "./opsfiles/disable-bpm.yml")

			healthCheckCmd := exec.Command(boshBinaryPath, []string{"--json", "ssh", "--results", "uaa", "-c", "/var/vcap/jobs/uaa/bin/health_check"}...)
			session, err := gexec.Start(healthCheckCmd, GinkgoWriter, GinkgoWriter)
			Expect(err).NotTo(HaveOccurred())
			Eventually(session, 5*time.Minute).Should(gexec.Exit(0))
		})
	})
})

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

	for ; ; {
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

func getNumOfOSCertificates() int {
	caCertificatesSSHStdoutCmd := exec.Command(boshBinaryPath, []string{"--json", "ssh", "--results", "uaa", "-c", "sudo grep 'END CERTIFICATE' /etc/ssl/certs/ca-certificates.crt | wc -l"}...)
	session, err := gexec.Start(caCertificatesSSHStdoutCmd, GinkgoWriter, GinkgoWriter)
	Expect(err).NotTo(HaveOccurred())
	Eventually(session, 10*time.Second).Should(gexec.Exit(0))

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
