package cmd

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"github.com/spf13/cobra"

	"github.com/kimmojae/qr2fa/internal/account"
	"github.com/kimmojae/qr2fa/internal/config"
	"github.com/kimmojae/qr2fa/internal/storage"
	"github.com/kimmojae/qr2fa/internal/tui"
)

var (
	// Global storage manager
	storageManager *storage.Manager
	// Custom data directory from flag
	dataDir string
)

// rootCmd represents the base command when called without any subcommands
var rootCmd = &cobra.Command{
	Use:   "qr2fa",
	Short: "TOTP MFA manager - QR capture & cloud sync",
	Long: `Terminal-based TOTP authenticator with QR capture and cloud sync.
Supports iCloud Drive, Dropbox, Google Drive, and more.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		// If no subcommand is provided, launch interactive TUI
		return runInteractiveTUI()
	},
}

// Execute adds all child commands to the root command and sets flags appropriately.
func Execute() {
	err := rootCmd.Execute()
	if err != nil {
		os.Exit(1)
	}
}

func init() {
	cobra.OnInitialize(initConfig)

	// Add global persistent flags
	rootCmd.PersistentFlags().StringVar(&dataDir, "data-dir", "",
		"Custom data directory (default: auto-detect iCloud Drive or ~/.qr2fa, can also use MFA_DATA_DIR env var)")
}

func initConfig() {
	// This will be called before each command runs
}

// initStorage initializes the storage manager
func initStorage() error {
	if storageManager != nil {
		return nil
	}

	// Determine data directory
	effectiveDataDir := dataDir

	// If no flag provided, check config file
	if effectiveDataDir == "" && os.Getenv("MFA_DATA_DIR") == "" {
		cfg, err := config.Load()
		if err != nil {
			return fmt.Errorf("failed to load config: %w", err)
		}

		// No config yet, prompt user
		if cfg == nil {
			selectedDir, err := promptDataDir()
			if err != nil {
				return err
			}

			// Save to config
			if err := config.Save(&config.Config{DataDir: selectedDir}); err != nil {
				return fmt.Errorf("failed to save config: %w", err)
			}

			fmt.Fprintf(os.Stderr, "✓ 설정 저장 완료\n\n")
			effectiveDataDir = selectedDir
		} else {
			effectiveDataDir = cfg.DataDir
		}
	}

	var err error
	storageManager, err = storage.NewManager(effectiveDataDir)
	if err != nil {
		return fmt.Errorf("failed to initialize storage: %w", err)
	}

	// Check if this is first run
	if !storageManager.Exists() {
		// Create empty storage
		st := account.NewStorage()
		if err := storageManager.Save(st); err != nil {
			return fmt.Errorf("failed to create initial storage: %w", err)
		}

		// Show where the data is stored
		fmt.Fprintf(os.Stderr, "Initialized storage at: %s\n", storageManager.GetStoragePath())
	}

	return nil
}

// promptDataDir prompts the user to select a data directory
func promptDataDir() (string, error) {
	return promptDataDirWithMessage(true)
}

// promptDataDirForChange prompts the user to change data directory
func promptDataDirForChange() (string, error) {
	return promptDataDirWithMessage(false)
}

// promptDataDirWithMessage prompts the user to select a data directory
func promptDataDirWithMessage(isFirstTime bool) (string, error) {
	if isFirstTime {
		fmt.Fprintf(os.Stderr, "\n⚠️  저장 경로가 설정되지 않았습니다.\n\n")
	} else {
		fmt.Fprintf(os.Stderr, "\n📁 저장 경로 변경\n\n")
	}
	fmt.Fprintf(os.Stderr, "데이터 저장 위치를 선택하세요:\n\n")

	iCloudPath := config.GetDefaultICloudPath()
	iCloudAvailable := config.IsICloudAvailable()

	fmt.Fprintf(os.Stderr, "1. iCloud Drive [추천]\n")
	fmt.Fprintf(os.Stderr, "   %s\n", iCloudPath)
	if iCloudAvailable {
		fmt.Fprintf(os.Stderr, "   Mac 간 자동 동기화\n")
	} else {
		fmt.Fprintf(os.Stderr, "   (iCloud Drive를 사용할 수 없습니다)\n")
	}
	fmt.Fprintf(os.Stderr, "\n")
	fmt.Fprintf(os.Stderr, "2. 직접 입력\n")
	fmt.Fprintf(os.Stderr, "   사용자 지정 경로 입력\n")
	fmt.Fprintf(os.Stderr, "\n")

	reader := bufio.NewReader(os.Stdin)
	fmt.Fprintf(os.Stderr, "선택 (1-2) [1]: ")

	input, err := reader.ReadString('\n')
	if err != nil {
		return "", fmt.Errorf("failed to read input: %w", err)
	}

	input = strings.TrimSpace(input)

	// Default to 1 if empty
	if input == "" {
		input = "1"
	}

	switch input {
	case "1":
		if !iCloudAvailable {
			fmt.Fprintf(os.Stderr, "\n⚠️  iCloud Drive를 사용할 수 없습니다. 로컬 경로(~/.qr2fa)를 사용합니다.\n")
			homeDir, _ := os.UserHomeDir()
			return homeDir + "/.qr2fa", nil
		}
		return iCloudPath, nil

	case "2":
		fmt.Fprintf(os.Stderr, "경로 입력: ")
		customPath, err := reader.ReadString('\n')
		if err != nil {
			return "", fmt.Errorf("failed to read custom path: %w", err)
		}

		customPath = strings.TrimSpace(customPath)
		if customPath == "" {
			return "", fmt.Errorf("경로를 입력해주세요")
		}

		// Expand ~ to home directory
		if strings.HasPrefix(customPath, "~/") {
			homeDir, _ := os.UserHomeDir()
			customPath = homeDir + customPath[1:]
		}

		return customPath, nil

	default:
		return "", fmt.Errorf("잘못된 선택입니다")
	}
}

// runInteractiveTUI launches the interactive TUI
func runInteractiveTUI() error {
	if err := initStorage(); err != nil {
		return err
	}

	// Load storage
	st, err := storageManager.Load()
	if err != nil {
		return fmt.Errorf("failed to load storage: %w", err)
	}

	// Launch TUI
	return tui.Run(st, storageManager)
}
