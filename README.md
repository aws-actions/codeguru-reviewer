# Amazon CodeGuru Reviewer for GitHub Actions

Amazon CodeGuru Reviewer finds issues in your Java and Python code and provides recommendations on how to remediate them. CodeGuru Reviewer identifies

1. Code quality issues, such as deviation from best practices with AWS APIs and SDKs, concurrency issues, resource leaks, and incorrect input validation
2. [Security vulnerabilities](https://aws.amazon.com/blogs/devops/tightening-application-security-with-amazon-codeguru/), such as risks from the top [10 OWASP categories](https://owasp.org/www-project-top-ten/).

Amazon CodeGuru Reviewer action can be triggered by a pull request, push, or scheduled run of your CI/CD pipeline.

* Pull requests - Code quality & security recommendations for your changed lines of code are shown in the pull request.
* Push - Code quality and security recommendations are shown in the security tab
* Manual / Scheduled runs - Code quality and security recommendations are shown in the security tab

To add CodeGuru Reviewer into your CI/CD pipeline, do the following.

## Usage

**Step 1: Set up Your workflow.yml File**

* **Add checkout to your workflow:**

For CodeGuru to run, check out your repository using [actions/checkout@v2](https://github.com/actions/checkout). **You will need to set fetch-depth: 0 to fetch all history for all branches and tags.** For example:
	 
```
 - name: Checkout repository
   uses: actions/checkout@v2
   with:
     fetch-depth: 0 # This is a required field for CodeGuru
```

* **Provide your AWS Credentials:**

We recommend following the instructions and using [aws-actions/configure-aws-credentials](https://github.com/aws-actions/configure-aws-credentials) to configure your credentials for a job. The IAM user or IAM role requires [AmazonCodeGuruReviewerFullAccess](http://amazoncodegurureviewerfullaccess/) policy and S3 permissions (s3:PutObject, s3:ListBucket, s3:GetObject) for the "codeguru-reviewer-*" S3 bucket.  The CodeGuru Reviewer action supports credentials from GitHub hosted runners and self-hosted runners.

**Step 2: Add Amazon CodeGuru Reviewer Action**

The source_path is assumed to be the root of the repository (e.g. ".").

Input Parameters:

* s3_bucket: **Required**. When you run a CodeGuru scan, your code is first uploaded into an S3 bucket in your AWS account. Provide the name of the S3 bucket you are using. Its name must begin with a prefix of “codeguru-reviewer-”. If you haven’t created a  bucket, you can create one using the bucket policy outlined in this CloudFormation template ([JSON](s3.template.json) or [YAML](s3.template.yml)) or by following these [instructions](https://docs.aws.amazon.com/AmazonS3/latest/userguide/create-bucket-overview.html). Your data is always protected with CodeGuru using these [data protection practices](https://docs.aws.amazon.com/codeguru/latest/reviewer-ug/data-protection.html).
* build_path: **Optional**. In order to receive security recommendations from CodeGuru, you will need to upload your code’s build artifact to the S3 bucket. Use this optional parameter to provide the build_path of the artifact. Your build files can be .jar or .class files.

- name: AWS CodeGuru Reviewer Scanner
uses: aws-actions/codeguru-reviewer@v1
with:
 build_path: target # build artifact(s) directory
 s3_bucket: 'codeguru-reviewer-myactions-bucket' # S3 Bucket with "codeguru-reviewer-*" prefix
 


**Step 3: Upload Results to GitHub**

After your job is completed, you can view your results within the AWS Console or GitHub. To view the results in GitHub, we recommend uploading the results generated in the SARIF (Static Analysis Results Interchange Format) into GitHub using the following example codeql-action. For more details, see the upload instructions in the [GitHub documentation](https://docs.github.com/en/code-security/secure-coding/uploading-a-sarif-file-to-github#example-workflow-for-sarif-files-generated-outside-of-a-repository).

```
- name: Upload review result
   uses: github/codeql-action/upload-sarif@v1
   with:
     sarif_file: codeguru-results.sarif.json # Your results file will be named codeguru-results.sarif.json
```

Example:

steps:

```
# Step 1: Checkout the repository and provide your AWS credentials
 - name: Checkout repository
   uses: actions/checkout@v2
   with:
     fetch-depth: 0

 - name: Configure AWS Credentials
   uses: aws-actions/configure-aws-credentials@v1
   with:
     aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
     aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
     aws-region: us-west-2  # Region to access CodeGuru 

# Step 2: Add CodeGuru Reviewer Action
 - name: AWS CodeGuru Reviewer Scanner
   uses: aws-actions/codeguru-reviewer@v1
   with:
     build_path: target # build artifact(s) directory
     s3_bucket: codeguru-reviewer-my-bucket  # S3 Bucket with "codeguru-reviewer-*" prefix
 
 # Step 3: Upload results into GitHub
 - name: Upload review result
   uses: github/codeql-action/upload-sarif@v1
   with:
     sarif_file: codeguru-results.sarif.json
```

## Recommendations

After you run the CodeGuru Reviewer Action, security findings and code quality recommendations are posted on the Security tab in the GitHub UI and in the Code Reviews section of the CodeGuru Reviewer console.

The following is an example of CodeGuru Reviewer recommendations for a Push or Schedule event on the Security tab in the GitHub UI.

![alt text](https://github.com/aws-actions/codeguru-reviewer/blob/Github-actions-release/images/recommendation_example_1.png)

The following is an example of CodeGuru Reviewer recommendations for a Pull Request event in the Pull Request view.

![alt text](https://github.com/aws-actions/codeguru-reviewer/blob/Github-actions-release/images/recommendation_example_2.png)

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the Apache-2.0 License. See the [LICENSE](LICENSE) file.