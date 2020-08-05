package module_test

import (
	"fmt"
	"testing"

	ecs "github.com/telia-oss/terraform-aws-ecs-fargate/v3/test"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
)

func TestModule(t *testing.T) {
	tests := []struct {
		description string
		directory   string
		name        string
		region      string
		expected    ecs.Expectations
	}{
		{
			description: "basic example",
			directory:   "../examples/basic",
			name:        fmt.Sprintf("fargate-basic-test-%s", random.UniqueId()),
			region:      "eu-west-1",
			expected: ecs.Expectations{
				DesiredTaskCount: 1,
				TaskCPU:          256,
				TaskMemory:       512,
				NetworkMode:      "awsvpc",
				ContainerImage:   "crccheck/hello-world:latest",
				ContainerEnvironment: map[string]string{
					"TEST_VARIABLE": "TEST_VALUE",
				},
				HTTPGetResponse: []string{
					`Hello World`,
					`~~~ {~~ ~~~~ ~~~ ~~~~ ~~ ~ /  ===- ~~~`,
					`\______ o          _,/`,
				},
			},
		},
		{
			description: "task secrets example",
			directory:   "../examples/secrets",
			name:        fmt.Sprintf("fargate-secrets-test-%s", random.UniqueId()),
			region:      "eu-west-1",
			expected: ecs.Expectations{
				DesiredTaskCount: 1,
				TaskCPU:          256,
				TaskMemory:       512,
				NetworkMode:      "awsvpc",
				ContainerImage:   "crccheck/hello-world:latest",
				ContainerEnvironment: map[string]string{
					"TEST_VARIABLE": "TEST_VALUE",
				},
				HTTPGetResponse: []string{
					`Hello World`,
					`~~~ {~~ ~~~~ ~~~ ~~~~ ~~ ~ /  ===- ~~~`,
					`\______ o          _,/`,
				},
			},
		},
	}

	for _, tc := range tests {
		tc := tc // Source: https://gist.github.com/posener/92a55c4cd441fc5e5e85f27bca008721
		t.Run(tc.description, func(t *testing.T) {
			t.Parallel()
			options := &terraform.Options{
				TerraformDir: tc.directory,

				Vars: map[string]interface{}{
					"name_prefix": tc.name,
					"region":      tc.region,
				},

				EnvVars: map[string]string{
					"AWS_DEFAULT_REGION": tc.region,
				},
			}

			defer terraform.Destroy(t, options)
			terraform.InitAndApply(t, options)

			ecs.RunTestSuite(t,
				terraform.Output(t, options, "cluster_arn"),
				terraform.Output(t, options, "service_arn"),
				fmt.Sprintf("http://%s", terraform.Output(t, options, "endpoint")),
				tc.region,
				tc.expected,
			)
		})
	}
}
