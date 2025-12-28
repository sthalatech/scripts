package main

import (
	"fmt"
	"io"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"
)

func main() {
	// Get configuration from environment variables
	apiKey := os.Getenv("API_KEY")
	if apiKey == "" {
		log.Fatal("API_KEY environment variable is required")
	}

	// Support both VLLM_URL and OLLAMA_URL for backward compatibility
	backendURL := os.Getenv("VLLM_URL")
	if backendURL == "" {
		backendURL = os.Getenv("OLLAMA_URL")
	}
	if backendURL == "" {
		backendURL = "http://localhost:11434"
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8000"
	}

	// Parse backend URL
	target, err := url.Parse(backendURL)
	if err != nil {
		log.Fatalf("Invalid backend URL: %v", err)
	}

	// Create reverse proxy
	proxy := httputil.NewSingleHostReverseProxy(target)

	// Custom error handler
	proxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
		log.Printf("Proxy error: %v", err)
		w.WriteHeader(http.StatusBadGateway)
		fmt.Fprintf(w, "Proxy error: %v", err)
	}

	// Authentication middleware
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		// Extract token from Authorization header
		authHeader := r.Header.Get("Authorization")
		if authHeader == "" {
			http.Error(w, "Missing Authorization header", http.StatusUnauthorized)
			return
		}

		// Check Bearer token
		token := strings.TrimPrefix(authHeader, "Bearer ")
		if token == authHeader || token != apiKey {
			http.Error(w, "Invalid API key", http.StatusUnauthorized)
			return
		}

		// Remove Authorization header before proxying
		r.Header.Del("Authorization")

		// Proxy the request
		proxy.ServeHTTP(w, r)
	})

	// Health check endpoint (no auth required)
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		io.WriteString(w, "OK")
	})

	log.Printf("vLLM Auth Proxy starting on port %s", port)
	log.Printf("Proxying to: %s", backendURL)
	log.Printf("API Key configured: %s...", apiKey[:min(8, len(apiKey))])

	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal(err)
	}
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
