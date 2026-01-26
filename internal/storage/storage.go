package storage

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/kimmojae/qr2fa/internal/account"
)

const (
	// DefaultStorageDir is the default directory for storing data
	DefaultStorageDir = ".qr2fa"
	// StorageFileName is the name of the storage file
	StorageFileName = "accounts.json"
)

// Manager handles storage operations
type Manager struct {
	storagePath string
}

// NewManager creates a new storage manager with optional custom data directory
func NewManager(customDataDir string) (*Manager, error) {
	storagePath, err := getStoragePath(customDataDir)
	if err != nil {
		return nil, err
	}

	return &Manager{
		storagePath: storagePath,
	}, nil
}

// getStoragePath returns the path to the storage file
// Priority: customDataDir > MFA_DATA_DIR env var > iCloud Drive > ~/.mfa
func getStoragePath(customDataDir string) (string, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("failed to get home directory: %w", err)
	}

	var dataDir string

	// Priority 1: Custom data directory (from flag)
	if customDataDir != "" {
		dataDir = customDataDir
	} else if envDataDir := os.Getenv("MFA_DATA_DIR"); envDataDir != "" {
		// Priority 2: Environment variable
		dataDir = envDataDir
	} else {
		// Priority 3: Try iCloud Drive first (macOS only)
		iCloudBase := filepath.Join(homeDir, "Library", "Mobile Documents", "com~apple~CloudDocs")
		if _, err := os.Stat(iCloudBase); err == nil {
			// iCloud Drive exists, use it
			dataDir = filepath.Join(iCloudBase, DefaultStorageDir)
		} else {
			// Priority 4: Fallback to home directory
			dataDir = filepath.Join(homeDir, DefaultStorageDir)
		}
	}

	// Ensure directory exists
	if err := os.MkdirAll(dataDir, 0700); err != nil {
		return "", fmt.Errorf("failed to create storage directory %s: %w", dataDir, err)
	}

	return filepath.Join(dataDir, StorageFileName), nil
}

// Load loads the storage
func (m *Manager) Load() (*account.Storage, error) {
	// Check if file exists
	if _, err := os.Stat(m.storagePath); os.IsNotExist(err) {
		// File doesn't exist, return empty storage
		return account.NewStorage(), nil
	}

	// Read file
	data, err := os.ReadFile(m.storagePath)
	if err != nil {
		return nil, fmt.Errorf("failed to read storage file: %w", err)
	}

	// Parse storage
	var storage account.Storage
	if err := json.Unmarshal(data, &storage); err != nil {
		return nil, fmt.Errorf("failed to parse storage: %w", err)
	}

	return &storage, nil
}

// Save saves the storage
func (m *Manager) Save(storage *account.Storage) error {
	// Ensure directory exists
	if err := os.MkdirAll(filepath.Dir(m.storagePath), 0700); err != nil {
		return fmt.Errorf("failed to create directory: %w", err)
	}

	// Serialize storage
	data, err := json.MarshalIndent(storage, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to serialize storage: %w", err)
	}

	// Write to temporary file first
	tempPath := m.storagePath + ".tmp"
	if err := os.WriteFile(tempPath, data, 0600); err != nil {
		return fmt.Errorf("failed to write temporary file: %w", err)
	}

	// Atomic rename
	if err := os.Rename(tempPath, m.storagePath); err != nil {
		os.Remove(tempPath) // Clean up temp file
		return fmt.Errorf("failed to rename file: %w", err)
	}

	return nil
}

// GetStoragePath returns the current storage path
func (m *Manager) GetStoragePath() string {
	return m.storagePath
}

// Exists checks if the storage file exists
func (m *Manager) Exists() bool {
	_, err := os.Stat(m.storagePath)
	return err == nil
}

// Export exports storage to a file (unencrypted JSON)
func (m *Manager) Export(storage *account.Storage, path string) error {
	data, err := json.MarshalIndent(storage, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to serialize storage: %w", err)
	}

	if err := os.WriteFile(path, data, 0600); err != nil {
		return fmt.Errorf("failed to write export file: %w", err)
	}

	return nil
}

// Import imports storage from a file (unencrypted JSON)
func (m *Manager) Import(path string) (*account.Storage, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read import file: %w", err)
	}

	var storage account.Storage
	if err := json.Unmarshal(data, &storage); err != nil {
		return nil, fmt.Errorf("failed to parse import file: %w", err)
	}

	return &storage, nil
}
