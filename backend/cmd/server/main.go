// Command server starts the Smart Office Queue REST API.
package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"smartoffice/internal/auth"
	"smartoffice/internal/config"
	"smartoffice/internal/db"
	"smartoffice/internal/handler"
	"smartoffice/internal/seed"
	"smartoffice/internal/service"
	"smartoffice/internal/store/postgres"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	pool, err := pgxpool.New(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("database: %v", err)
	}
	defer pool.Close()
	if err := pool.Ping(ctx); err != nil {
		log.Fatalf("database ping failed (is PostgreSQL running and DATABASE_URL correct?): %v", err)
	}
	if err := db.Migrate(ctx, pool); err != nil {
		log.Fatalf("migrations: %v", err)
	}

	repo := postgres.New(pool)
	if cfg.SeedOnStart {
		if err := seed.Run(ctx, repo, cfg.SeedPass); err != nil {
			log.Fatalf("seed: %v", err)
		}
	}

	jwtManager := auth.NewManager(cfg.JWTSecret, cfg.JWTTTL)
	api := &handler.API{
		Queue:       service.NewQueue(repo),
		Auth:        auth.NewService(repo, jwtManager),
		JWT:         jwtManager,
		CORSOrigins: cfg.CORSOrigins,
	}

	srv := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           api.Routes(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      30 * time.Second,
	}
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = srv.Shutdown(shutdownCtx)
	}()

	log.Printf("Smart Office Queue API listening on http://localhost:%s", cfg.Port)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("server: %v", err)
	}
}
