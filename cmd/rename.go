package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

// renameCmd represents the rename command
var renameCmd = &cobra.Command{
	Use:   "rename <number> <new-name>",
	Short: "Rename an MFA account",
	Long:  `Rename an existing MFA account. Use the account number from 'qr2fa list'.`,
	Args:  cobra.ExactArgs(2),
	RunE: func(cmd *cobra.Command, args []string) error {
		newName := args[1]

		if err := initStorage(); err != nil {
			return err
		}

		st, err := storageManager.Load()
		if err != nil {
			return fmt.Errorf("failed to load storage: %w", err)
		}

		// Find account by number
		acc, err := findAccountByID(st, args[0])
		if err != nil {
			return err
		}

		oldName := acc.Name
		acc.Name = newName

		// Save storage
		if err := storageManager.Save(st); err != nil {
			return fmt.Errorf("failed to save storage: %w", err)
		}

		fmt.Printf("✓ Renamed '%s' to '%s'\n", oldName, newName)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(renameCmd)
}
