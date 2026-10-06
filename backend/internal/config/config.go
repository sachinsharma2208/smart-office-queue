// Package config loads settings from environment variables (optionally from a
// local .env file). Nothing secret is hard-coded.
package config

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	Port        string
	DatabaseURL string
	JWTSecret   string
	JWTTTL      time.Duration
	CORSOrigins string
	SeedOnStart bool
	SeedPass    string
}

// Load reads .env (if present; existing environment variables win) and then
// validates the environment.
func Load() (*Config, error) {
	loadDotEnv(".env")
	c := &Config{
		Port:        get("PORT", "8080"),
		DatabaseURL: os.Getenv("DATABASE_URL"),
		JWTSecret:   os.Getenv("JWT_SECRET"),
		CORSOrigins: get("CORS_ALLOWED_ORIGINS", "*"),
		SeedOnStart: strings.EqualFold(os.Getenv("SEED_ON_START"), "true"),
		SeedPass:    os.Getenv("SEED_PASSWORD"),
	}
	hours, err := strconv.Atoi(get("JWT_TTL_HOURS", "12"))
	if err != nil || hours <= 0 {
		return nil, errors.New("JWT_TTL_HOURS must be a positive integer")
	}
	c.JWTTTL = time.Duration(hours) * time.Hour

	if c.DatabaseURL == "" {
		return nil, errors.New("DATABASE_URL is required (see .env.example)")
	}
	if len(c.JWTSecret) < 16 {
		return nil, errors.New("JWT_SECRET is required and must be at least 16 characters (see .env.example)")
	}
	if c.SeedOnStart && len(c.SeedPass) < 8 {
		return nil, fmt.Errorf("SEED_PASSWORD (min 8 chars) is required when SEED_ON_START=true")
	}
	return c, nil
}

func get(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// loadDotEnv is a minimal KEY=VALUE loader so the project needs no extra dependency.
func loadDotEnv(path string) {
	f, err := os.Open(path)
	if err != nil {
		return
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		k, v = strings.TrimSpace(k), strings.Trim(strings.TrimSpace(v), `"'`)
		if _, set := os.LookupEnv(k); !set {
			_ = os.Setenv(k, v)
		}
	}
}
