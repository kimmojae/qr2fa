package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/kimmojae/qr2fa/internal/config"
)

// configCmd represents the config command
var configCmd = &cobra.Command{
	Use:   "config",
	Short: "Manage configuration",
	Long:  `Manage qr2fa configuration settings.`,
}

// configShowCmd shows current configuration
var configShowCmd = &cobra.Command{
	Use:   "show",
	Short: "Show current configuration",
	RunE: func(cmd *cobra.Command, args []string) error {
		cfg, err := config.Load()
		if err != nil {
			return fmt.Errorf("failed to load config: %w", err)
		}

		if cfg == nil {
			fmt.Println("⚠️  설정이 없습니다.")
			fmt.Println()
			fmt.Println("다음 명령어를 실행하면 설정 프롬프트가 나타납니다:")
			fmt.Println("  qr2fa list")
			fmt.Println()
			fmt.Println("또는 직접 설정:")
			fmt.Println("  qr2fa config set-path")
			return nil
		}

		fmt.Println("현재 설정:")
		fmt.Println()
		fmt.Printf("데이터 디렉토리: %s\n", cfg.DataDir)

		// Check if directory exists
		if _, err := os.Stat(cfg.DataDir); os.IsNotExist(err) {
			fmt.Println("상태: ⚠️  디렉토리가 존재하지 않습니다")
		} else {
			fmt.Println("상태: ✓ 정상")
		}

		configPath, _ := config.GetConfigPath()
		fmt.Println()
		fmt.Printf("설정 파일: %s\n", configPath)

		return nil
	},
}

// configSetPathCmd sets the data directory
var configSetPathCmd = &cobra.Command{
	Use:   "set-path [directory]",
	Short: "Set data directory",
	Long:  `Set the data directory for storing accounts. If no directory is provided, an interactive prompt will be shown.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		var newPath string

		if len(args) > 0 {
			// Direct path provided
			newPath = args[0]
		} else {
			// Interactive prompt
			var err error
			newPath, err = promptDataDirForChange()
			if err != nil {
				return err
			}
		}

		// Save config
		if err := config.Save(&config.Config{DataDir: newPath}); err != nil {
			return fmt.Errorf("failed to save config: %w", err)
		}

		fmt.Println()
		fmt.Printf("✓ 데이터 디렉토리 변경 완료: %s\n", newPath)

		configPath, _ := config.GetConfigPath()
		fmt.Printf("✓ 설정 저장: %s\n", configPath)

		return nil
	},
}

// configResetCmd resets the configuration
var configResetCmd = &cobra.Command{
	Use:   "reset",
	Short: "Reset configuration",
	Long:  `Reset configuration. The next time you run qr2fa, you will be prompted to select a data directory.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		configPath, err := config.GetConfigPath()
		if err != nil {
			return fmt.Errorf("failed to get config path: %w", err)
		}

		// Check if config exists
		if _, err := os.Stat(configPath); os.IsNotExist(err) {
			fmt.Println("⚠️  설정 파일이 없습니다.")
			return nil
		}

		// Remove config file
		if err := os.Remove(configPath); err != nil {
			return fmt.Errorf("failed to remove config file: %w", err)
		}

		fmt.Println("✓ 설정 초기화 완료")
		fmt.Println()
		fmt.Println("다음 실행 시 데이터 디렉토리를 다시 선택하게 됩니다.")

		return nil
	},
}

func init() {
	rootCmd.AddCommand(configCmd)
	configCmd.AddCommand(configShowCmd)
	configCmd.AddCommand(configSetPathCmd)
	configCmd.AddCommand(configResetCmd)
}
