package cmd

import (
	"fmt"
	"strings"

	"github.com/spf13/cobra"
)

// editCmd represents the edit command
var editCmd = &cobra.Command{
	Use:   "edit <number>",
	Short: "Edit an MFA account's tag",
	Long:  `Edit the tag of an existing MFA account. Use the account number from 'qr2fa list'.`,
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
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

		fmt.Fprintf(cmd.ErrOrStderr(), "Account: %s\n", acc.DisplayName())

		// Prompt for new tag
		currentTag := acc.Tag
		if currentTag == "" {
			currentTag = "(없음)"
		}
		fmt.Fprintf(cmd.ErrOrStderr(), "Tag [%s]: ", currentTag)
		tag := readLine()
		if tag != "" {
			acc.Tag = strings.ToLower(strings.TrimSpace(tag))
		}

		// Save storage
		if err := storageManager.Save(st); err != nil {
			return fmt.Errorf("failed to save storage: %w", err)
		}

		fmt.Fprintf(cmd.ErrOrStderr(), "✓ Account '%s' updated successfully\n", acc.DisplayName())
		return nil
	},
}

func init() {
	rootCmd.AddCommand(editCmd)
}
