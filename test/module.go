package module

import (
	"io/ioutil"
	"net/http"
	"strconv"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/ecs"
	"github.com/stretchr/testify/assert"
)

type Expectations struct {
	DesiredTaskCount int64
	TaskCPU          int
	TaskMemory       int
	ContainerImage   string
	NetworkMode      string
	GetResponse      []string
	Tags             map[string]string
}

func RunTestSuite(t *testing.T, clusterARN, serviceARN, endpoint, region string, expected Expectations) {
	var (
		service             *ecs.Service
		taskDefinition      *ecs.TaskDefinition
		containerDefinition *ecs.ContainerDefinition
	)
	sess := NewSession(t, region)

	service = DescribeService(t, sess, clusterARN, serviceARN)
	assert.Equal(t, "ACTIVE", aws.StringValue(service.Status))
	assert.Equal(t, expected.DesiredTaskCount, aws.Int64Value(service.DesiredCount))

	taskDefinition = DescribeTaskDefinition(t, sess, aws.StringValue(service.TaskDefinition))
	assert.Equal(t, strconv.Itoa(expected.TaskCPU), aws.StringValue(taskDefinition.Cpu))
	assert.Equal(t, strconv.Itoa(expected.TaskMemory), aws.StringValue(taskDefinition.Memory))
	assert.Equal(t, expected.NetworkMode, aws.StringValue(taskDefinition.NetworkMode))

	containerDefinition = GetContainerDefinition(t, taskDefinition)
	assert.Equal(t, expected.ContainerImage, aws.StringValue(containerDefinition.Image))

	WaitForRunningTasks(t, sess, clusterARN, serviceARN, 10*time.Second, 10*time.Minute)

	response := GetServiceEndpoint(t, endpoint)
	for _, line := range expected.GetResponse {
		assert.Contains(t, response, line)
	}
}

func NewSession(t *testing.T, region string) *session.Session {
	sess, err := session.NewSession(&aws.Config{
		Region: aws.String(region),
	})
	if err != nil {
		t.Fatalf("failed to create new AWS session: %s", err)
	}
	return sess
}

func DescribeService(t *testing.T, sess *session.Session, clusterARN, serviceARN string) *ecs.Service {
	c := ecs.New(sess)

	out, err := c.DescribeServices(&ecs.DescribeServicesInput{
		Cluster:  aws.String(clusterARN),
		Services: []*string{aws.String(serviceARN)},
	})
	if err != nil {
		t.Fatalf("failed to describe service: %s", err)
	}
	if n := len(out.Services); n != 1 {
		t.Fatalf("found wrong number (%d) of matches for service: %s", n, serviceARN)
	}
	var service *ecs.Service
	for _, s := range out.Services {
		if arn := aws.StringValue(s.ServiceArn); arn != serviceARN {
			t.Fatalf("wrong service arn: %s", arn)
		}
		service = s
	}
	return service
}

func GetServiceTags(service *ecs.Service) map[string]string {
	tags := make(map[string]string)
	for _, t := range service.Tags {
		tags[aws.StringValue(t.Key)] = aws.StringValue(t.Value)
	}
	return tags
}

func DescribeTaskDefinition(t *testing.T, sess *session.Session, taskDefinitionARN string) *ecs.TaskDefinition {
	c := ecs.New(sess)

	out, err := c.DescribeTaskDefinition(&ecs.DescribeTaskDefinitionInput{
		TaskDefinition: aws.String(taskDefinitionARN),
	})
	if err != nil {
		t.Fatalf("failed to describe task definition: %s", err)
	}
	return out.TaskDefinition
}

func GetContainerDefinition(t *testing.T, taskDefinition *ecs.TaskDefinition) *ecs.ContainerDefinition {
	if n := len(taskDefinition.ContainerDefinitions); n != 1 {
		t.Fatalf("task has wrong number of container definitions: %d", n)
	}
	return taskDefinition.ContainerDefinitions[0]
}

func WaitForRunningTasks(t *testing.T, sess *session.Session, clusterARN, serviceARN string, checkInterval time.Duration, timeoutLimit time.Duration) {
	interval := time.NewTicker(checkInterval)
	defer interval.Stop()

	timeout := time.NewTimer(timeoutLimit)
	defer timeout.Stop()

WaitLoop:
	for {
		select {
		case <-interval.C:
			t.Log("waiting for running tasks...")
			service := DescribeService(t, sess, clusterARN, serviceARN)
			if aws.Int64Value(service.DesiredCount) == aws.Int64Value(service.RunningCount) {
				break WaitLoop
			}
		case <-timeout.C:
			t.Fatal("timeout reached while waiting for the desired number of running tasks")
		}
	}
}

func GetServiceEndpoint(t *testing.T, endpoint string) string {
	r, err := http.Get(endpoint)
	if err != nil {
		t.Fatalf("get-request error: %s", err)
	}
	defer r.Body.Close()

	if r.StatusCode != http.StatusOK {
		t.Errorf("got non-200 response: %d", r.StatusCode)
	}

	body, err := ioutil.ReadAll(r.Body)
	if err != nil {
		t.Fatalf("failed to read response body: %s", err)
	}
	return string(body)
}
