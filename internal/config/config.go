package config

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

const (
	// ConfigDir is the config directory name
	ConfigDir = ".config/qr2fa"
	// ConfigFileName is the config file name
	ConfigFileName = "config.json"
)

// Config represents the application configuration
type Config struct {
	DataDir string `json:"data_dir"`
}

// Load loads the config from file
func Load() (*Config, error) {
	configPath, err := GetConfigPath()
	if err != nil {
		return nil, err
	}

	// Check if config file exists
	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		return nil, nil // No config file yet
	}

	data, err := os.ReadFile(configPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}

	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("failed to parse config: %w", err)
	}

	return &cfg, nil
}

// Save saves the config to file
func Save(cfg *Config) error {
	configPath, err := GetConfigPath()
	if err != nil {
		return err
	}

	// Ensure config directory exists
	if err := os.MkdirAll(filepath.Dir(configPath), 0700); err != nil {
		return fmt.Errorf("failed to create config directory: %w", err)
	}

	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to serialize config: %w", err)
	}

	if err := os.WriteFile(configPath, data, 0600); err != nil {
		return fmt.Errorf("failed to write config file: %w", err)
	}

	return nil
}

// GetConfigPath returns the path to the config file
func GetConfigPath() (string, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("failed to get home directory: %w", err)
	}

	return filepath.Join(homeDir, ConfigDir, ConfigFileName), nil
}

// GetDefaultICloudPath returns the default iCloud Drive path
func GetDefaultICloudPath() string {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return ""
	}

	return filepath.Join(homeDir, "Library", "Mobile Documents", "com~apple~CloudDocs", ".qr2fa")
}

// IsICloudAvailable checks if iCloud Drive is available
func IsICloudAvailable() bool {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return false
	}

	iCloudBase := filepath.Join(homeDir, "Library", "Mobile Documents", "com~apple~CloudDocs")
	_, err = os.Stat(iCloudBase)
	return err == nil
}
