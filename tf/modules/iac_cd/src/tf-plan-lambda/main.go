package main

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/credentials/stscreds"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/codepipeline"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/aws/aws-sdk-go/service/s3/s3manager"
	"github.com/aws/aws-sdk-go/service/sts"
)

type UserParameters struct {
	Environment string `json:"environment"`
	AccountID   string `json:"account_id"`
	CommitSHA   string `json:"commit_sha"`
	Branch      string `json:"branch"`
	Author      string `json:"author"`
}

type PlanSummary struct {
	Environment string `json:"environment"`
	AccountID   string `json:"account_id"`
	CommitSHA   string `json:"commit_sha"`
	Branch      string `json:"branch"`
	Author      string `json:"author"`
	Success     bool   `json:"success"`
	Error       string `json:"error,omitempty"`
	PlanOutput  string `json:"plan_output"`
}

func handler(ctx context.Context, event events.CodePipelineJobEvent) error {
	job := event.CodePipelineJob
	jobID := job.ID
	jobData := job.Data

	// Parse user parameters
	var userParams UserParameters
	if err := json.Unmarshal([]byte(jobData.ActionConfiguration.Configuration["UserParameters"]), &userParams); err != nil {
		return reportFailure(jobID, fmt.Sprintf("Failed to parse user parameters: %v", err))
	}

	// Get input artifact location
	inputArtifact := jobData.InputArtifacts[0]
	bucket := inputArtifact.Location.S3Location.BucketName
	key := inputArtifact.Location.S3Location.ObjectKey

	// Get output artifact location
	outputArtifact := jobData.OutputArtifacts[0]
	outputBucket := outputArtifact.Location.S3Location.BucketName
	outputKey := outputArtifact.Location.S3Location.ObjectKey

	// Create temporary directory
	tempDir, err := os.MkdirTemp("", "terraform-plan-*")
	if err != nil {
		return reportFailure(jobID, fmt.Sprintf("Failed to create temp dir: %v", err))
	}
	defer os.RemoveAll(tempDir)

	// Download and extract artifact
	if err := downloadAndExtract(bucket, key, tempDir); err != nil {
		return reportFailure(jobID, fmt.Sprintf("Failed to download artifact: %v", err))
	}

	// Set up AWS session for target account
	sess, err := getSessionForAccount(userParams.AccountID)
	if err != nil {
		return reportFailure(jobID, fmt.Sprintf("Failed to set up AWS session: %v", err))
	}

	// Run terraform plan
	planOutput, err := runTerraformPlan(tempDir, userParams.Environment, sess)
	if err != nil {
		// Even if plan fails, we want to save the output
		summary := PlanSummary{
			Environment: userParams.Environment,
			AccountID:   userParams.AccountID,
			CommitSHA:   userParams.CommitSHA,
			Branch:      userParams.Branch,
			Author:      userParams.Author,
			Success:     false,
			Error:       err.Error(),
			PlanOutput:  planOutput,
		}
		if uploadErr := uploadResults(outputBucket, outputKey, summary); uploadErr != nil {
			return reportFailure(jobID, fmt.Sprintf("Plan failed and could not upload results: %v", uploadErr))
		}
		return reportFailure(jobID, fmt.Sprintf("Terraform plan failed: %v", err))
	}

	// Create success summary
	summary := PlanSummary{
		Environment: userParams.Environment,
		AccountID:   userParams.AccountID,
		CommitSHA:   userParams.CommitSHA,
		Branch:      userParams.Branch,
		Author:      userParams.Author,
		Success:     true,
		PlanOutput:  planOutput,
	}

	// Upload results
	if err := uploadResults(outputBucket, outputKey, summary); err != nil {
		return reportFailure(jobID, fmt.Sprintf("Failed to upload results: %v", err))
	}

	// Report success
	return reportSuccess(jobID)
}

func downloadAndExtract(bucket, key, destDir string) error {
	sess := session.Must(session.NewSession())
	downloader := s3manager.NewDownloader(sess)

	// Download file
	zipPath := filepath.Join(destDir, "terraform.zip")
	file, err := os.Create(zipPath)
	if err != nil {
		return fmt.Errorf("failed to create file: %w", err)
	}
	defer file.Close()

	_, err = downloader.Download(file, &s3.GetObjectInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(key),
	})
	if err != nil {
		return fmt.Errorf("failed to download file: %w", err)
	}

	// Extract zip
	return unzip(zipPath, destDir)
}

func unzip(src, dest string) error {
	r, err := zip.OpenReader(src)
	if err != nil {
		return err
	}
	defer r.Close()

	for _, f := range r.File {
		fpath := filepath.Join(dest, f.Name)

		if !strings.HasPrefix(fpath, filepath.Clean(dest)+string(os.PathSeparator)) {
			return fmt.Errorf("illegal file path: %s", fpath)
		}

		if f.FileInfo().IsDir() {
			os.MkdirAll(fpath, os.ModePerm)
			continue
		}

		if err := os.MkdirAll(filepath.Dir(fpath), os.ModePerm); err != nil {
			return err
		}

		outFile, err := os.OpenFile(fpath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, f.Mode())
		if err != nil {
			return err
		}

		rc, err := f.Open()
		if err != nil {
			return err
		}

		_, err = io.Copy(outFile, rc)
		outFile.Close()
		rc.Close()

		if err != nil {
			return err
		}
	}
	return nil
}

func getSessionForAccount(targetAccountID string) (*session.Session, error) {
	sess := session.Must(session.NewSession())
	stsClient := sts.New(sess)

	// Get current account ID
	identity, err := stsClient.GetCallerIdentity(&sts.GetCallerIdentityInput{})
	if err != nil {
		return nil, fmt.Errorf("failed to get caller identity: %w", err)
	}

	currentAccountID := aws.StringValue(identity.Account)
	
	// If same account, return current session
	if currentAccountID == targetAccountID {
		return sess, nil
	}

	// Otherwise, assume role in target account
	roleName := os.Getenv("CROSS_ACCOUNT_ROLE_NAME")
	if roleName == "" {
		return nil, fmt.Errorf("CROSS_ACCOUNT_ROLE_NAME not set")
	}

	roleArn := fmt.Sprintf("arn:aws:iam::%s:role/%s", targetAccountID, roleName)
	creds := stscreds.NewCredentials(sess, roleArn)
	
	return session.NewSession(&aws.Config{
		Credentials: creds,
	})
}

func runTerraformPlan(workDir, environment string, sess *session.Session) (string, error) {
	// Use the bundled OpenTofu binary
	tofuPath := "/var/task/tofu"
	if _, err := os.Stat(tofuPath); os.IsNotExist(err) {
		return "", fmt.Errorf("opentofu binary not found at %s", tofuPath)
	}

	// Set working directory
	tfDir := filepath.Join(workDir, "tf", environment)
	if _, err := os.Stat(tfDir); os.IsNotExist(err) {
		return "", fmt.Errorf("environment directory not found: %s", tfDir)
	}

	// Get AWS credentials from session
	creds, err := sess.Config.Credentials.Get()
	if err != nil {
		return "", fmt.Errorf("failed to get credentials: %w", err)
	}

	// Set up environment variables
	env := os.Environ()
	env = append(env, fmt.Sprintf("AWS_ACCESS_KEY_ID=%s", creds.AccessKeyID))
	env = append(env, fmt.Sprintf("AWS_SECRET_ACCESS_KEY=%s", creds.SecretAccessKey))
	if creds.SessionToken != "" {
		env = append(env, fmt.Sprintf("AWS_SESSION_TOKEN=%s", creds.SessionToken))
	}

	// Run tofu init
	initCmd := exec.Command(tofuPath, "init", "-backend=false")
	initCmd.Dir = tfDir
	initCmd.Env = env
	
	var initOut bytes.Buffer
	initCmd.Stdout = &initOut
	initCmd.Stderr = &initOut
	
	if err := initCmd.Run(); err != nil {
		return initOut.String(), fmt.Errorf("tofu init failed: %w\nOutput: %s", err, initOut.String())
	}

	// Prepare tofu plan command
	planArgs := []string{"plan", "-out=tfplan", "-no-color"}
	
	// Add environment-specific variables
	switch environment {
	case "dev", "prod":
		if toolsAccountID := os.Getenv("TOOLS_ACCOUNT_ID"); toolsAccountID != "" {
			planArgs = append(planArgs, fmt.Sprintf("-var=tools_account_id=%s", toolsAccountID))
		}
	case "tools":
		if devAccountID := os.Getenv("DEV_ACCOUNT_ID"); devAccountID != "" {
			planArgs = append(planArgs, fmt.Sprintf("-var=dev_account_id=%s", devAccountID))
		}
		if prodAccountID := os.Getenv("PROD_ACCOUNT_ID"); prodAccountID != "" {
			planArgs = append(planArgs, fmt.Sprintf("-var=prod_account_id=%s", prodAccountID))
		}
	}

	// Run tofu plan
	planCmd := exec.Command(tofuPath, planArgs...)
	planCmd.Dir = tfDir
	planCmd.Env = env
	
	var planOut bytes.Buffer
	planCmd.Stdout = &planOut
	planCmd.Stderr = &planOut
	
	err = planCmd.Run()
	planOutput := planOut.String()
	
	if err != nil {
		return planOutput, fmt.Errorf("tofu plan failed: %w", err)
	}

	// Show the plan file to get human-readable output
	showCmd := exec.Command(tofuPath, "show", "-no-color", "tfplan")
	showCmd.Dir = tfDir
	showCmd.Env = env
	
	var showOut bytes.Buffer
	showCmd.Stdout = &showOut
	showCmd.Stderr = &showOut
	
	if err := showCmd.Run(); err != nil {
		// If show fails, return the plan output we already have
		return planOutput, nil
	}

	return showOut.String(), nil
}

func uploadResults(bucket, key string, summary PlanSummary) error {
	sess := session.Must(session.NewSession())
	uploader := s3manager.NewUploader(sess)

	// Create temporary zip file
	tempFile, err := os.CreateTemp("", "plan-result-*.zip")
	if err != nil {
		return fmt.Errorf("failed to create temp file: %w", err)
	}
	defer os.Remove(tempFile.Name())

	// Create zip writer
	zipWriter := zip.NewWriter(tempFile)

	// Add summary.json
	summaryData, err := json.MarshalIndent(summary, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal summary: %w", err)
	}

	summaryFile, err := zipWriter.Create("summary.json")
	if err != nil {
		return fmt.Errorf("failed to create summary file: %w", err)
	}
	if _, err := summaryFile.Write(summaryData); err != nil {
		return fmt.Errorf("failed to write summary: %w", err)
	}

	// Add plan_output.txt
	planFile, err := zipWriter.Create("plan_output.txt")
	if err != nil {
		return fmt.Errorf("failed to create plan file: %w", err)
	}
	if _, err := planFile.Write([]byte(summary.PlanOutput)); err != nil {
		return fmt.Errorf("failed to write plan output: %w", err)
	}

	// Close zip
	if err := zipWriter.Close(); err != nil {
		return fmt.Errorf("failed to close zip: %w", err)
	}

	// Upload to S3
	tempFile.Seek(0, 0)
	_, err = uploader.Upload(&s3manager.UploadInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(key),
		Body:   tempFile,
	})

	return err
}

func reportSuccess(jobID string) error {
	sess := session.Must(session.NewSession())
	cp := codepipeline.New(sess)

	_, err := cp.PutJobSuccessResult(&codepipeline.PutJobSuccessResultInput{
		JobId: aws.String(jobID),
	})
	return err
}

func reportFailure(jobID, message string) error {
	sess := session.Must(session.NewSession())
	cp := codepipeline.New(sess)

	_, err := cp.PutJobFailureResult(&codepipeline.PutJobFailureResultInput{
		JobId: aws.String(jobID),
		FailureDetails: &codepipeline.FailureDetails{
			Message: aws.String(message),
		},
	})
	return err
}

func main() {
	lambda.Start(handler)
}