package cmd

import (
	"fmt"
	"sort"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/spf13/cobra"

	"github.com/kimmojae/qr2fa/internal/totp"
)

var (
	listTag string
)

// listCmd represents the list command
var listCmd = &cobra.Command{
	Use:   "list",
	Short: "List all MFA accounts",
	Long:  `List all MFA accounts with their current TOTP codes and remaining time.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		if err := initStorage(); err != nil {
			return err
		}

		st, err := storageManager.Load()
		if err != nil {
			return fmt.Errorf("failed to load storage: %w", err)
		}

		accounts := st.Accounts
		if listTag != "" {
			accounts = st.FilterByTag(listTag)
		}

		if len(accounts) == 0 {
			if listTag != "" {
				fmt.Println("No accounts found with tag:", listTag)
			} else {
				fmt.Println("No accounts found. Add one with 'qr2fa add'")
			}
			return nil
		}

		// Sort by name
		sort.Slice(accounts, func(i, j int) bool {
			return strings.ToLower(accounts[i].Name) < strings.ToLower(accounts[j].Name)
		})

		// Print accounts
		for _, acc := range accounts {
			code, err := totp.Generate(acc)
			if err != nil {
				fmt.Printf("%-30s ERROR\n", acc.DisplayName())
				continue
			}

			remaining := totp.RemainingSeconds(acc)
			formattedCode := totp.FormatCode(code)

			// Color based on remaining time
			var codeStyle lipgloss.Style
			if remaining > 12 {
				codeStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("10")) // Green
			} else if remaining > 5 {
				codeStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("11")) // Yellow
			} else {
				codeStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("9")) // Red
			}

			fmt.Printf("%-30s %s  (%ds)\n", acc.DisplayName(), codeStyle.Render(formattedCode), remaining)
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(listCmd)
	listCmd.Flags().StringVarP(&listTag, "tag", "t", "", "Filter by tag (dev/prod/staging/personal)")
}
