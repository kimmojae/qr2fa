package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var (
	importMerge bool
)

// importCmd represents the import command
var importCmd = &cobra.Command{
	Use:   "import <filename>",
	Short: "Import accounts from a JSON file",
	Long:  `Import MFA accounts from a JSON file. By default, this will merge with existing accounts.`,
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		filename := args[0]

		if err := initStorage(); err != nil {
			return err
		}

		// Load current storage
		st, err := storageManager.Load()
		if err != nil {
			return fmt.Errorf("failed to load storage: %w", err)
		}

		// Import from file
		importedSt, err := storageManager.Import(filename)
		if err != nil {
			return fmt.Errorf("failed to import: %w", err)
		}

		// Merge accounts
		imported := 0
		skipped := 0
		for _, acc := range importedSt.Accounts {
			// Check for duplicates
			if st.FindBySecret(acc.Secret) != nil {
				if importMerge {
					skipped++
					continue
				}
			}

			if err := st.Add(acc); err != nil {
				// Skip duplicates
				skipped++
				continue
			}
			imported++
		}

		// Save storage
		if err := storageManager.Save(st); err != nil {
			return fmt.Errorf("failed to save storage: %w", err)
		}

		fmt.Printf("✓ Imported %d accounts", imported)
		if skipped > 0 {
			fmt.Printf(" (%d skipped due to duplicates)", skipped)
		}
		fmt.Println()

		return nil
	},
}

func init() {
	rootCmd.AddCommand(importCmd)
	importCmd.Flags().BoolVarP(&importMerge, "merge", "m", true, "Merge with existing accounts (skip duplicates)")
}
