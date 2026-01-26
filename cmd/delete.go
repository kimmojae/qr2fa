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
	Use:   "delete <account-name>",
	Short: "Delete an MFA account",
	Long:  `Delete an MFA account from storage.`,
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

		// Check if account exists
		acc := st.FindByName(accountName)
		if acc == nil {
			return fmt.Errorf("account '%s' not found", accountName)
		}

		// Confirm deletion unless -f is used
		if !forceDelete {
			fmt.Printf("Delete account '%s'? (y/N): ", acc.Name)
			confirmation := readLine()
			if !strings.EqualFold(confirmation, "y") && !strings.EqualFold(confirmation, "yes") {
				fmt.Println("Cancelled")
				return nil
			}
		}

		// Delete account
		if err := st.Delete(accountName); err != nil {
			return fmt.Errorf("failed to delete account: %w", err)
		}

		// Save storage
		if err := storageManager.Save(st); err != nil {
			return fmt.Errorf("failed to save storage: %w", err)
		}

		fmt.Printf("✓ Account '%s' deleted successfully\n", acc.Name)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(deleteCmd)
	deleteCmd.Flags().BoolVarP(&forceDelete, "force", "f", false, "Skip confirmation prompt")
}
