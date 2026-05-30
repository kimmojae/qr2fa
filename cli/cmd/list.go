package cmd

import (
	"fmt"
	"sort"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/spf13/cobra"

	"github.com/kimmojae/qr2fa/internal/account"
	"github.com/kimmojae/qr2fa/internal/totp"
)

var tagColors = map[string]lipgloss.Color{
	"dev":  lipgloss.Color("12"), // Blue
	"prod": lipgloss.Color("9"),  // Red
}

func formatAccountDisplay(acc *account.Account) string {
	issuer := acc.Issuer
	if issuer == "" {
		issuer = "n/a"
	}

	display := issuer
	if acc.Tag != "" {
		color, ok := tagColors[acc.Tag]
		if !ok {
			color = lipgloss.Color("14") // Cyan for unknown tags
		}
		tagStyle := lipgloss.NewStyle().Foreground(color)
		display = fmt.Sprintf("%s %s", display, tagStyle.Render("["+acc.Tag+"]"))
	}

	display = fmt.Sprintf("%-28s %s", display, acc.Name)
	return display
}

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

		// Sort by issuer then name for display
		sort.Slice(accounts, func(i, j int) bool {
			if accounts[i].Issuer != accounts[j].Issuer {
				return strings.ToLower(accounts[i].Issuer) < strings.ToLower(accounts[j].Issuer)
			}
			return strings.ToLower(accounts[i].Name) < strings.ToLower(accounts[j].Name)
		})

		if listTag != "" {
			var filtered []*account.Account
			for _, acc := range accounts {
				if strings.EqualFold(acc.Tag, listTag) {
					filtered = append(filtered, acc)
				}
			}
			accounts = filtered
		}

		// Print accounts grouped by issuer
		issuerStyle := lipgloss.NewStyle().Bold(true)
		currentIssuer := ""
		for _, acc := range accounts {
			issuer := acc.Issuer
			if issuer == "" {
				issuer = "n/a"
			}

			// Print issuer header when group changes
			if issuer != currentIssuer {
				if currentIssuer != "" {
					fmt.Println() // blank line between groups
				}
				fmt.Println(issuerStyle.Render(issuer))
				currentIssuer = issuer
			}

			// Format tag
			tagStr := ""
			if acc.Tag != "" {
				color, ok := tagColors[acc.Tag]
				if !ok {
					color = lipgloss.Color("14")
				}
				tagStyle := lipgloss.NewStyle().Foreground(color)
				tagStr = tagStyle.Render("["+acc.Tag+"]") + " "
			}

			code, err := totp.Generate(acc)
			if err != nil {
				fmt.Printf("  #%-2d %s%-20s ERROR\n", acc.ID, tagStr, acc.Name)
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

			fmt.Printf("  #%-2d %s%-20s %s  (%ds)\n", acc.ID, tagStr, acc.Name, codeStyle.Render(formattedCode), remaining)
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(listCmd)
	listCmd.Flags().StringVarP(&listTag, "tag", "t", "", "Filter by tag (dev/prod/...)")
}
