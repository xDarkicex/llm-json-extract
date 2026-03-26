package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"time"
)

type requestBody struct {
	Raw string `json:"raw"`
}

type errorResponse struct {
	Error string `json:"error"`
}

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
	})
	mux.HandleFunc("/extract", extractHandler)

	addr := ":8080"
	log.Printf("net/http example listening on %s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatal(err)
	}
}

func extractHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, errorResponse{Error: "method_not_allowed"})
		return
	}

	defer r.Body.Close()
	var req requestBody
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "invalid_json_body"})
		return
	}
	if strings.TrimSpace(req.Raw) == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "raw_is_required"})
		return
	}

	stdout, stderr, exitCode, err := runExtractor(req.Raw)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]any{
			"error":     "extract_exec_failed",
			"details":   err.Error(),
			"stderr":    stderr,
			"exit_code": exitCode,
		})
		return
	}

	if !json.Valid([]byte(stdout)) {
		writeJSON(w, http.StatusBadGateway, map[string]any{
			"error":     "extractor_returned_non_json",
			"extractor": strings.TrimSpace(stdout),
			"stderr":    stderr,
			"exit_code": exitCode,
		})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = io.WriteString(w, stdout)
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

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
