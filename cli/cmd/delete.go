package cmd

import (
	"fmt"
	"strings"

	"github.com/spf13/cobra"
)

var (
	forceDelete bool
)

// deleteCmd represents the delete command
var deleteCmd = &cobra.Command{
	Use:   "delete <number>",
	Short: "Delete an MFA account",
	Long:  `Delete an MFA account from storage. Use the account number from 'qr2fa list'.`,
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

		// Confirm deletion unless -f is used
		if !forceDelete {
			fmt.Printf("Delete '%s'? (y/N): ", acc.DisplayName())
			confirmation := readLine()
			if !strings.EqualFold(confirmation, "y") && !strings.EqualFold(confirmation, "yes") {
				fmt.Println("Cancelled")
				return nil
			}
		}

		// Delete account by ID
		for i, a := range st.Accounts {
			if a.ID == acc.ID {
				st.Accounts = append(st.Accounts[:i], st.Accounts[i+1:]...)
				break
			}
		}

		// Save storage
		if err := storageManager.Save(st); err != nil {
			return fmt.Errorf("failed to save storage: %w", err)
		}

		fmt.Printf("✓ Account '%s' deleted successfully\n", acc.DisplayName())
		return nil
	},
}

func init() {
	rootCmd.AddCommand(deleteCmd)
	deleteCmd.Flags().BoolVarP(&forceDelete, "force", "f", false, "Skip confirmation prompt")
}
