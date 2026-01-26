package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

// exportCmd represents the export command
var exportCmd = &cobra.Command{
	Use:   "export <filename>",
	Short: "Export all accounts to a JSON file",
	Long:  `Export all MFA accounts to an unencrypted JSON file for backup purposes.`,
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		filename := args[0]

		if err := initStorage(); err != nil {
			return err
		}

		st, err := storageManager.Load()
		if err != nil {
			return fmt.Errorf("failed to load storage: %w", err)
		}

		if err := storageManager.Export(st, filename); err != nil {
			return fmt.Errorf("failed to export: %w", err)
		}

		fmt.Printf("✓ Exported %d accounts to %s\n", len(st.Accounts), filename)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(exportCmd)
}
