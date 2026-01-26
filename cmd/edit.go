package cmd

import (
	"fmt"
	"strings"

	"github.com/spf13/cobra"
)

// editCmd represents the edit command
var editCmd = &cobra.Command{
	Use:   "edit <account-name>",
	Short: "Edit an MFA account",
	Long:  `Edit an existing MFA account (name and tag).`,
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		accountName := args[0]

		if err := initStorage(); err != nil {
			return err
		}

		st, err := storageManager.Load()
		if err != nil {
			return fmt.Errorf("failed to load storage: %w", err)
		}

		// Find account
		acc := st.FindByName(accountName)
		if acc == nil {
			return fmt.Errorf("account '%s' not found", accountName)
		}

		// Prompt for new name
		fmt.Fprintf(cmd.ErrOrStderr(), "Name [%s]: ", acc.Name)
		name := readLine()
		if name != "" {
			// Check if new name already exists
			if existing := st.FindByName(name); existing != nil && existing.ID != acc.ID {
				return fmt.Errorf("account with name '%s' already exists", name)
			}
			acc.Name = name
		}

		// Prompt for new tag
		fmt.Fprintf(cmd.ErrOrStderr(), "Tag [%s]: ", acc.Tag)
		tag := readLine()
		if tag != "" {
			acc.Tag = strings.ToLower(strings.TrimSpace(tag))
		}

		// Save storage
		if err := storageManager.Save(st); err != nil {
			return fmt.Errorf("failed to save storage: %w", err)
		}

		fmt.Fprintf(cmd.ErrOrStderr(), "✓ Account '%s' updated successfully\n", acc.Name)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(editCmd)
}
