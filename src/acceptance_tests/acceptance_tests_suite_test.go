package acceptance_tests_test

import (
	"testing"

	"encoding/json"
	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"github.com/onsi/gomega/gexec"
	"io/ioutil"
	"os"
	"os/exec"
	"strings"
	"time"

	"fmt"
	boshdir "github.com/cloudfoundry/bosh-cli/director"
	boshlog "github.com/cloudfoundry/bosh-utils/logger"
	"github.com/onsi/gomega/gbytes"
)

func TestAcceptanceTests(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "AcceptanceTests Suite")
}

var (
	boshBinaryPath = "bosh"

	directorURL    string
	directorIP     string
	directorCACert string

	directorClient       string
	directorClientSecret string

	deployCmd = []string{"-n", "deploy", "/tmp/uaa-deployment.yml", "-o", "./opsfiles/enable-local-uaa.yml", "--vars-store=/tmp/uaa-store.json", "-v", "system_domain=localhost"}
	deleteCmd = []string{"-n", "delete-deployment", "-d", "uaa"}
)

var _ = BeforeSuite(func() {
	setBoshEnvironmentVariables()

	By("disabling bosh resurrection", func() {
		disableResurrectionCmd := exec.Command(boshBinaryPath, "-d", "uaa", "update-resurrection", "-n", "off")
		session, err := gexec.Start(disableResurrectionCmd, GinkgoWriter, GinkgoWriter)
		Expect(err).NotTo(HaveOccurred())
		Eventually(session, 5*time.Minute).Should(gexec.Exit(0))
	})
})

func setBoshEnvironmentVariables() {
	var envFound bool

	directorURL, envFound = os.LookupEnv("BOSH_ENVIRONMENT")
	Expect(envFound).To(BeTrue(), "BOSH_ENVIRONMENT was not set")

	directorIP, envFound = os.LookupEnv("BOSH_DIRECTOR_IP")
	Expect(envFound).To(BeTrue(), "BOSH_DIRECTOR_IP was not set")

	_, envFound = os.LookupEnv("BOSH_DEPLOYMENT")
	Expect(envFound).To(BeTrue(), "BOSH_DEPLOYMENT was not set")

	directorClient, envFound = os.LookupEnv("BOSH_CLIENT")
	Expect(envFound).To(BeTrue(), "BOSH_CLIENT was not set")

	directorClientSecret, envFound = os.LookupEnv("BOSH_CLIENT_SECRET")
	Expect(envFound).To(BeTrue(), "BOSH_CLIENT_SECRET was not set")

	boshCACert, envFound := os.LookupEnv("BOSH_CA_CERT")
	Expect(envFound).To(BeTrue(), "BOSH_CA_CERT was not set")

	boshCACertContents, err := ioutil.ReadFile(boshCACert)
	Expect(err).NotTo(HaveOccurred())
	directorCACert = string(boshCACertContents)

	director, err := buildDirector(directorIP)
	Expect(err).NotTo(HaveOccurred())

	info, err := director.Info()
	Expect(err).NotTo(HaveOccurred())
	Expect(info.Name).To(Equal("docker"))
	Expect(info.User).To(Equal("admin"))
}

type instanceInfo struct {
	IP            string
	InstanceID    string
	InstanceGroup string
	Index         string
	ProcessState  string
}

func buildDirector(directorIP string) (boshdir.Director, error) {
	logger := boshlog.NewLogger(boshlog.LevelError)
	factory := boshdir.NewFactory(logger)

	config, err := boshdir.NewConfigFromURL(directorIP)
	if err != nil {
		return nil, err
	}

	config.Client = directorClient
	config.ClientSecret = directorClientSecret
	config.CACert = directorCACert

	return factory.New(config, boshdir.NewNoopTaskReporter(), boshdir.NewNoopFileReporter())
}

func getInstanceInfos(boshBinary string) []instanceInfo {
	cmd := exec.Command(boshBinary, "instances", "--details", "--json")
	session, err := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	Expect(err).NotTo(HaveOccurred())
	Eventually(session, 20*time.Second).Should(gexec.Exit(0))

	var response struct {
		Tables []struct {
			Rows []map[string]string
		}
	}

	var out []instanceInfo
	json.Unmarshal(session.Out.Contents(), &response)

	for _, row := range response.Tables[0].Rows {
		instanceStrings := strings.Split(row["instance"], "/")

		out = append(out, instanceInfo{
			IP:            row["ips"],
			InstanceGroup: instanceStrings[0],
			InstanceID:    instanceStrings[1],
			Index:         row["index"],
			ProcessState:  row["process_state"],
		})
	}

	return out
}

func getUaaIP() (string, bool) {
	instanceInfos := getInstanceInfos(boshBinaryPath)
	for _, instanceInfo := range instanceInfos {
		if strings.Contains(instanceInfo.InstanceGroup, "uaa") {
			return instanceInfo.IP, true
		}
	}

	return "", false
}

func deployUAA(opsFiles ...string) {
	session := boshDeploy(opsFiles...)
	Eventually(session, 20*time.Minute).Should(gexec.Exit(0))
	Eventually(session).Should(gbytes.Say("Preparing deployment: Preparing deployment"))
}

func boshDeploy(optFiles ...string) *gexec.Session {
	updatedDeployCmd := make([]string, len(deployCmd))
	copy(updatedDeployCmd, deployCmd)
	for _, optFile := range optFiles {
		updatedDeployCmd = append(updatedDeployCmd, "-o", optFile)
	}

	var session *gexec.Session
	var err error
	By(fmt.Sprintf("deploying uaa: %v", updatedDeployCmd), func() {
		os.Remove("/tmp/uaa-store.json")
		cmd := exec.Command(boshBinaryPath, updatedDeployCmd...)
		session, err = gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
		Expect(err).NotTo(HaveOccurred())
	})
	return session
}

func addLocalDNS(uaaDomainName string) {
	uaaIp, found := getUaaIP()
	Expect(found).To(BeTrue())
	etcHosts, err := os.OpenFile("/etc/hosts", os.O_RDWR|os.O_APPEND, os.ModePerm)
	Expect(err).NotTo(HaveOccurred())
	_, err = etcHosts.WriteString(fmt.Sprintf("%s %s\n", uaaIp, uaaDomainName))
	Expect(err).NotTo(HaveOccurred())
}
