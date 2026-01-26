package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

// renameCmd represents the rename command
var renameCmd = &cobra.Command{
	Use:   "rename <old-name> <new-name>",
	Short: "Rename an MFA account",
	Long:  `Rename an existing MFA account.`,
	Args:  cobra.ExactArgs(2),
	RunE: func(cmd *cobra.Command, args []string) error {
		oldName := args[0]
		newName := args[1]

		if err := initStorage(); err != nil {
			return err
		}

		st, err := storageManager.Load()
		if err != nil {
			return fmt.Errorf("failed to load storage: %w", err)
		}

		// Find account
		acc := st.FindByName(oldName)
		if acc == nil {
			return fmt.Errorf("account '%s' not found", oldName)
		}

		// Check if new name already exists
		if st.FindByName(newName) != nil {
			return fmt.Errorf("account with name '%s' already exists", newName)
		}

		// Update name
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
