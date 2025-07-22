package main

import (
    "archive/zip"
    "bytes"
    "context"
    "encoding/json"
    "fmt"
    "github.com/aws/aws-sdk-go/aws/credentials"
    "io"
    "os"
    "os/exec"
    "path/filepath"
    "strings"

    "github.com/aws/aws-lambda-go/lambda"
    "github.com/aws/aws-sdk-go/aws"
    "github.com/aws/aws-sdk-go/aws/session"
    "github.com/aws/aws-sdk-go/service/codepipeline"
    "github.com/aws/aws-sdk-go/service/s3"
    "github.com/aws/aws-sdk-go/service/s3/s3manager"
    "github.com/aws/aws-sdk-go/service/ssm"
)

// CodePipeline event structure
type CodePipelineEvent struct {
    CodePipelineJob struct {
        ID   string `json:"id"`
        Data struct {
            ActionConfiguration struct {
                Configuration map[string]string `json:"configuration"`
            } `json:"actionConfiguration"`
            InputArtifacts []struct {
                Name     string `json:"name"`
                Location struct {
                    S3Location struct {
                        BucketName string `json:"bucketName"`
                        ObjectKey  string `json:"objectKey"`
                    } `json:"s3Location"`
                } `json:"location"`
            } `json:"inputArtifacts"`
            OutputArtifacts []struct {
                Name     string `json:"name"`
                Location struct {
                    S3Location struct {
                        BucketName string `json:"bucketName"`
                        ObjectKey  string `json:"objectKey"`
                    } `json:"s3Location"`
                } `json:"location"`
            } `json:"outputArtifacts"`
            ArtifactCredentials struct {
                AccessKeyID     string `json:"accessKeyId"`
                SecretAccessKey string `json:"secretAccessKey"`
                SessionToken    string `json:"sessionToken"`
            } `json:"artifactCredentials"`
        } `json:"data"`
    } `json:"CodePipeline.job"`
}

type UserParameters struct {
    Env          string `json:"env"`
    Org          string `json:"org"`
    AccountID    string `json:"account_id"`
    MetadataPath string `json:"metadata_path"`
}

type Metadata struct {
    Timestamp     string `json:"timestamp"`
    CommitSHA     string `json:"commit_sha"`
    ShortSHA      string `json:"short_sha"`
    Branch        string `json:"branch"`
    Author        string `json:"author"`
    AuthorEmail   string `json:"author_email"`
    CommitMessage string `json:"commit_message"`
    PRNumber      string `json:"pr_number"`
    GitHubRunID   string `json:"github_run_id"`
    GitHubRunURL  string `json:"github_run_url"`
}

type PlanSummary struct {
    Env        string `json:"env"`
    AccountID  string `json:"account_id"`
    CommitSHA  string `json:"commit_sha"`
    Branch     string `json:"branch"`
    Author     string `json:"author"`
    Success    bool   `json:"success"`
    Error      string `json:"error,omitempty"`
    PlanOutput string `json:"plan_output"`
}

func handler(ctx context.Context, event CodePipelineEvent) error {
    job := event.CodePipelineJob
    jobID := job.ID
    jobData := job.Data

    fmt.Printf("Starting Lambda execution for job ID: %s\n", jobID)

    // Parse user parameters
    var userParams UserParameters
    userParamsStr, ok := jobData.ActionConfiguration.Configuration["UserParameters"]
    if !ok {
        return reportFailure(jobID, "UserParameters not found in action configuration")
    }

    if err := json.Unmarshal([]byte(userParamsStr), &userParams); err != nil {
        return reportFailure(jobID, fmt.Sprintf("Failed to parse user parameters: %v", err))
    }

    fmt.Printf("User parameters: env=%s, metadata_path=%s\n", userParams.Env, userParams.MetadataPath)

    // Get input artifact location
    if len(jobData.InputArtifacts) == 0 {
        return reportFailure(jobID, "No input artifacts found")
    }
    inputArtifact := jobData.InputArtifacts[0]
    bucket := inputArtifact.Location.S3Location.BucketName
    key := inputArtifact.Location.S3Location.ObjectKey

    // Get output artifact location
    if len(jobData.OutputArtifacts) == 0 {
        return reportFailure(jobID, "No output artifacts found")
    }
    outputArtifact := jobData.OutputArtifacts[0]
    outputBucket := outputArtifact.Location.S3Location.BucketName
    outputKey := outputArtifact.Location.S3Location.ObjectKey

    // Create temporary directory
    tempDir, err := os.MkdirTemp("", "terraform-plan-*")
    if err != nil {
        return reportFailure(jobID, fmt.Sprintf("Failed to create temp dir: %v", err))
    }
    defer os.RemoveAll(tempDir)

    // Get artifact credentials from CodePipeline
    artifactCreds := jobData.ArtifactCredentials

    // Download and extract artifact
    fmt.Printf("Downloading artifact from s3://%s/%s\n", bucket, key)
    if err := downloadAndExtract(bucket, key, tempDir, artifactCreds); err != nil {
        return reportFailure(jobID, fmt.Sprintf("Failed to download artifact: %v", err))
    }
    fmt.Printf("Artifact extracted to: %s\n", tempDir)

    // Read metadata from specified path (default to metadata.json)
    metadataPath := userParams.MetadataPath
    if metadataPath == "" {
        metadataPath = "metadata.json"
    }
    metadata, err := readMetadata(filepath.Join(tempDir, metadataPath))
    if err != nil {
        return reportFailure(jobID, fmt.Sprintf("Failed to read metadata: %v", err))
    }

    // Run terraform plan
    planOutput, err := runTerraformPlan(tempDir, userParams)
    if err != nil {
        // Even if plan fails, we want to save the output
        summary := PlanSummary{
            Env:        userParams.Env,
            CommitSHA:  metadata.CommitSHA,
            Branch:     metadata.Branch,
            Author:     metadata.Author,
            Success:    false,
            Error:      err.Error(),
            PlanOutput: planOutput,
        }
        if uploadErr := uploadResults(outputBucket, outputKey, summary, jobData.ArtifactCredentials); uploadErr != nil {
            return reportFailure(jobID, fmt.Sprintf("Plan failed and could not upload results: %v", uploadErr))
        }
        return reportFailure(jobID, fmt.Sprintf("Terraform plan failed: %v", err))
    }

    // Create success summary
    summary := PlanSummary{
        Env:        userParams.Env,
        CommitSHA:  metadata.CommitSHA,
        Branch:     metadata.Branch,
        Author:     metadata.Author,
        Success:    true,
        PlanOutput: planOutput,
    }

    // Upload results
    if err := uploadResults(outputBucket, outputKey, summary, jobData.ArtifactCredentials); err != nil {
        return reportFailure(jobID, fmt.Sprintf("Failed to upload results: %v", err))
    }

    // Report success
    return reportSuccess(jobID)
}

func downloadAndExtract(bucket, key, destDir string, creds struct {
    AccessKeyID     string `json:"accessKeyId"`
    SecretAccessKey string `json:"secretAccessKey"`
    SessionToken    string `json:"sessionToken"`
}) error {
    // Use the temporary credentials provided by CodePipeline
    sess := session.Must(session.NewSession(&aws.Config{
        Credentials: credentials.NewStaticCredentials(
            creds.AccessKeyID,
            creds.SecretAccessKey,
            creds.SessionToken,
        ),
    }))
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

// Removed getSessionForAccount - Lambda runs in the target account

// loadParametersFromSSM reads all parameters from Parameter Store and returns them as TF_VAR_ env vars
func loadParametersFromSSM() (map[string]string, error) {
    parameterPrefix := os.Getenv("PARAMETER_STORE_PREFIX")
    if parameterPrefix == "" {
        // No parameters to load
        return nil, nil
    }

    sess := session.Must(session.NewSession())
    ssmClient := ssm.New(sess)

    envVars := make(map[string]string)

    // Get all parameters by path
    input := &ssm.GetParametersByPathInput{
        Path:           aws.String(parameterPrefix),
        Recursive:      aws.Bool(true),
        WithDecryption: aws.Bool(true),
    }

    err := ssmClient.GetParametersByPathPages(input, func(page *ssm.GetParametersByPathOutput, lastPage bool) bool {
        for _, param := range page.Parameters {
            // Extract the parameter name without the prefix
            paramName := strings.TrimPrefix(*param.Name, parameterPrefix+"/")
            // Set as TF_VAR_ environment variable
            envVars[fmt.Sprintf("TF_VAR_%s", paramName)] = *param.Value
        }
        return !lastPage
    })

    if err != nil {
        return nil, fmt.Errorf("failed to load parameters from SSM: %w", err)
    }

    return envVars, nil
}

func runTerraformPlan(workDir string, params UserParameters) (string, error) {
    // Use the bundled OpenTofu binary
    tofuPath := "/var/task/tofu"
    if _, err := os.Stat(tofuPath); os.IsNotExist(err) {
        return "", fmt.Errorf("opentofu binary not found at %s", tofuPath)
    }

    // List contents of workDir for debugging
    fmt.Printf("Contents of workDir %s:\n", workDir)
    files, _ := os.ReadDir(workDir)
    for _, f := range files {
        if f.IsDir() {
            fmt.Printf("  [DIR] %s\n", f.Name())
        } else {
            fmt.Printf("  [FILE] %s\n", f.Name())
        }
    }

    // Try multiple possible directory structures
    var tfDir string
    possiblePaths := []string{
        filepath.Join(workDir, "environments", params.Env),
        filepath.Join(workDir, "tf", "environments", params.Env),
        filepath.Join(workDir, "tf", params.Env),
        filepath.Join(workDir, params.Env),
    }

    for _, path := range possiblePaths {
        if _, err := os.Stat(path); err == nil {
            tfDir = path
            fmt.Printf("Found terraform directory at: %s\n", tfDir)
            break
        }
    }

    if tfDir == "" {
        return "", fmt.Errorf("environment directory not found in any of: %v", possiblePaths)
    }

    // Use current environment variables (Lambda already has the right credentials)
    env := os.Environ()

    // Load sensitive parameters from SSM and add to environment
    ssmParams, err := loadParametersFromSSM()
    if err != nil {
        return "", fmt.Errorf("failed to load SSM parameters: %w", err)
    }

    // Add SSM parameters to environment
    for k, v := range ssmParams {
        env = append(env, fmt.Sprintf("%s=%s", k, v))
    }

    fmt.Printf("Loaded %d parameters from SSM\n", len(ssmParams))

    // Run tofu init with no color output and non-interactive mode
    initCmd := exec.Command(tofuPath, "init", "-no-color", "-input=false")
    initCmd.Dir = tfDir
    initCmd.Env = env

    var initOut bytes.Buffer
    initCmd.Stdout = &initOut
    initCmd.Stderr = &initOut

    if err := initCmd.Run(); err != nil {
        output := initOut.String()
        // Include the actual output in the error message, not just "exit status 1"
        return output, fmt.Errorf("tofu init failed: %s", output)
    }

    // Prepare tofu plan command
    planArgs := []string{"plan", "-out=tfplan", "-no-color", "-input=false"}

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
        // Include the actual output in the error message
        return planOutput, fmt.Errorf("tofu plan failed: %s", planOutput)
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

func uploadResults(bucket, key string, summary PlanSummary, creds struct {
    AccessKeyID     string `json:"accessKeyId"`
    SecretAccessKey string `json:"secretAccessKey"`
    SessionToken    string `json:"sessionToken"`
}) error {
    // Use the temporary credentials provided by CodePipeline
    sess := session.Must(session.NewSession(&aws.Config{
        Credentials: credentials.NewStaticCredentials(
            creds.AccessKeyID,
            creds.SecretAccessKey,
            creds.SessionToken,
        ),
    }))
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
    fmt.Printf("Reporting SUCCESS to CodePipeline for job %s\n", jobID)
    sess := session.Must(session.NewSession())
    cp := codepipeline.New(sess)

    _, err := cp.PutJobSuccessResult(&codepipeline.PutJobSuccessResultInput{
        JobId: aws.String(jobID),
    })
    if err != nil {
        fmt.Printf("ERROR: Failed to report success to CodePipeline: %v\n", err)
    }
    return err
}

func reportFailure(jobID, message string) error {
    fmt.Printf("Reporting FAILURE to CodePipeline for job %s: %s\n", jobID, message)
    sess := session.Must(session.NewSession())
    cp := codepipeline.New(sess)

    // Truncate message if it's too long (CodePipeline has a 5000 character limit)
    const maxMessageLength = 4900 // Leave some buffer
    if len(message) > maxMessageLength {
        message = message[:maxMessageLength] + "... (truncated)"
    }

    _, err := cp.PutJobFailureResult(&codepipeline.PutJobFailureResultInput{
        JobId: aws.String(jobID),
        FailureDetails: &codepipeline.FailureDetails{
            Message: aws.String(message),
            Type:    aws.String("JobFailed"),
        },
    })
    if err != nil {
        fmt.Printf("ERROR: Failed to report failure to CodePipeline: %v\n", err)
    }
    return err
}

func readMetadata(metadataPath string) (Metadata, error) {
    var metadata Metadata

    // Read metadata file - must exist
    data, err := os.ReadFile(metadataPath)
    if err != nil {
        return metadata, fmt.Errorf("failed to read metadata file %s: %w", metadataPath, err)
    }

    // Parse the JSON
    if err := json.Unmarshal(data, &metadata); err != nil {
        return metadata, fmt.Errorf("failed to parse metadata JSON: %w", err)
    }

    return metadata, nil
}

func main() {
    lambda.Start(handler)
}
