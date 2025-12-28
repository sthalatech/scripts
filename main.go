package main

import (
	"crypto/subtle"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
)

func main() {
	apiKey := os.Getenv("API_KEY")
	if apiKey == "" {
		log.Fatal("API_KEY environment variable required")
	}

	ollamaURL := os.Getenv("OLLAMA_URL")
	if ollamaURL == "" {
		ollamaURL = "http://localhost:11434"
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8000"
	}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		// Check API key from Authorization header (Bearer token) or X-API-Key header
		auth := r.Header.Get("Authorization")
		xApiKey := r.Header.Get("X-API-Key")
		
		valid := false
		if strings.HasPrefix(auth, "Bearer ") {
			token := strings.TrimPrefix(auth, "Bearer ")
			valid = subtle.ConstantTimeCompare([]byte(token), []byte(apiKey)) == 1
		}
		if xApiKey != "" {
			valid = valid || subtle.ConstantTimeCompare([]byte(xApiKey), []byte(apiKey)) == 1
		}

		if !valid {
			w.Header().Set("WWW-Authenticate", `Bearer realm="ollama"`)
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		// Proxy the request
		proxyReq, err := http.NewRequest(r.Method, ollamaURL+r.URL.Path, r.Body)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		// Copy headers (except auth)
		for k, vv := range r.Header {
			if k == "Authorization" || k == "X-Api-Key" {
				continue
			}
			for _, v := range vv {
				proxyReq.Header.Add(k, v)
			}
		}
		proxyReq.URL.RawQuery = r.URL.RawQuery

		resp, err := http.DefaultClient.Do(proxyReq)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadGateway)
			return
		}
		defer resp.Body.Close()

		// Copy response headers
		for k, vv := range resp.Header {
			for _, v := range vv {
				w.Header().Add(k, v)
			}
		}
		w.WriteHeader(resp.StatusCode)
		io.Copy(w, resp.Body)
	})

	log.Printf("Starting ollama proxy on :%s (upstream: %s)", port, ollamaURL)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}
