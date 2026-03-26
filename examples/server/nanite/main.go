package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/xDarkicex/nanite"
)

type requestBody struct {
	Raw string `json:"raw"`
}

func main() {
	r := nanite.New(
		nanite.WithPanicRecovery(true),
	)

	r.Get("/health", func(c *nanite.Context) {
		c.JSON(200, map[string]any{"ok": true})
	})

	r.Post("/extract", func(c *nanite.Context) {
		var req requestBody
		if err := c.Bind(&req); err != nil {
			c.JSON(400, map[string]any{"error": "invalid_json_body"})
			return
		}
		if strings.TrimSpace(req.Raw) == "" {
			c.JSON(400, map[string]any{"error": "raw_is_required"})
			return
		}

		stdout, stderr, exitCode, err := runExtractor(req.Raw)
		if err != nil {
			c.JSON(502, map[string]any{
				"error":     "extract_exec_failed",
				"details":   err.Error(),
				"stderr":    stderr,
				"exit_code": exitCode,
			})
			return
		}

		if !json.Valid([]byte(stdout)) {
			c.JSON(502, map[string]any{
				"error":     "extractor_returned_non_json",
				"extractor": strings.TrimSpace(stdout),
				"stderr":    stderr,
				"exit_code": exitCode,
			})
			return
		}

		c.SetHeader("Content-Type", "application/json")
		c.String(200, stdout)
	})

	r.Start("8081")
}

func runExtractor(raw string) (stdout string, stderr string, exitCode int, err error) {
	extractorPath := os.Getenv("EXTRACTOR_PATH")
	if extractorPath == "" {
		extractorPath = "../../../llm-json-extract.pl"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	cmd := exec.CommandContext(
		ctx,
		"perl",
		extractorPath,
		"--meta",
		"--fallback-empty",
		"--timeout", "2",
		"--max-size", "10M",
		"--max-candidate", "2M",
		"--max-repair-size", "1M",
	)
	cmd.Stdin = strings.NewReader(raw)

	outBytes, runErr := cmd.Output()
	stdout = string(outBytes)

	if runErr == nil {
		return stdout, "", 0, nil
	}

	if ee, ok := runErr.(*exec.ExitError); ok {
		stderr = string(ee.Stderr)
		return stdout, stderr, ee.ExitCode(), fmt.Errorf("extractor exited with code %d", ee.ExitCode())
	}

	return stdout, "", -1, runErr
}
