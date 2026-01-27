package tui

import (
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/atotto/clipboard"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/kimmojae/qr2fa/internal/account"
	"github.com/kimmojae/qr2fa/internal/storage"
	"github.com/kimmojae/qr2fa/internal/totp"
)

// Model represents the TUI state
type Model struct {
	storage        *account.Storage
	storageManager *storage.Manager
	accounts       []*account.Account
	filteredAccs   []*account.Account
	cursor         int
	searchText     string
	width          int
	height         int
	message        string
	err            error
}

type tickMsg time.Time

// Run starts the TUI
func Run(st *account.Storage, sm *storage.Manager) error {
	m := &Model{
		storage:        st,
		storageManager: sm,
		accounts:       st.Accounts,
	}

	// Sort accounts by name
	sort.Slice(m.accounts, func(i, j int) bool {
		return strings.ToLower(m.accounts[i].Name) < strings.ToLower(m.accounts[j].Name)
	})

	m.filteredAccs = m.accounts

	p := tea.NewProgram(m, tea.WithAltScreen())
	_, err := p.Run()
	return err
}

func (m *Model) Init() tea.Cmd {
	return tickCmd()
}

func (m *Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		return m.handleKeyPress(msg)
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil
	case tickMsg:
		return m, tickCmd()
	}
	return m, nil
}

func (m *Model) handleKeyPress(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "ctrl+c", "q":
		return m, tea.Quit
	case "up", "k":
		if m.cursor > 0 {
			m.cursor--
		}
	case "down", "j":
		if m.cursor < len(m.filteredAccs)-1 {
			m.cursor++
		}
	case "enter":
		if len(m.filteredAccs) > 0 && m.cursor < len(m.filteredAccs) {
			acc := m.filteredAccs[m.cursor]
			code, err := totp.Generate(acc)
			if err != nil {
				m.message = fmt.Sprintf("Error: %v", err)
			} else {
				if err := clipboard.WriteAll(code); err != nil {
					m.message = fmt.Sprintf("Code: %s (clipboard failed)", code)
				} else {
					m.message = fmt.Sprintf("✓ Code %s copied to clipboard", code)
				}
			}
		}
	case "backspace":
		if len(m.searchText) > 0 {
			m.searchText = m.searchText[:len(m.searchText)-1]
			m.filterAccounts()
		}
	default:
		// Add character to search
		if len(msg.Runes) == 1 && msg.Runes[0] >= 32 && msg.Runes[0] <= 126 {
			m.searchText += string(msg.Runes[0])
			m.filterAccounts()
		}
	}
	return m, nil
}

func (m *Model) filterAccounts() {
	if m.searchText == "" {
		m.filteredAccs = m.accounts
		m.cursor = 0
		return
	}

	search := strings.ToLower(m.searchText)
	m.filteredAccs = []*account.Account{}
	for _, acc := range m.accounts {
		if strings.Contains(strings.ToLower(acc.Name), search) ||
			strings.Contains(strings.ToLower(acc.Issuer), search) ||
			strings.Contains(strings.ToLower(acc.Tag), search) {
			m.filteredAccs = append(m.filteredAccs, acc)
		}
	}

	if m.cursor >= len(m.filteredAccs) {
		m.cursor = len(m.filteredAccs) - 1
	}
	if m.cursor < 0 {
		m.cursor = 0
	}
}

func (m *Model) View() string {
	var s strings.Builder

	// Top padding
	s.WriteString("\n")

	// Title
	titleStyle := lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("99"))
	s.WriteString(titleStyle.Render("qr2fa") + "\n\n")

	// Search bar
	searchStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("240"))
	s.WriteString(searchStyle.Render("Search: ") + m.searchText + "\n\n")

	// Accounts list
	if len(m.filteredAccs) == 0 {
		s.WriteString("No accounts found.\n")
	} else {
		for i, acc := range m.filteredAccs {
			code, _ := totp.Generate(acc)
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

			cursor := " "
			if i == m.cursor {
				cursor = "▶"
				s.WriteString(lipgloss.NewStyle().Reverse(true).Render(
					fmt.Sprintf(" %s %-30s %s  (%ds)", cursor, acc.DisplayName(), formattedCode, remaining),
				) + "\n")
			} else {
				s.WriteString(fmt.Sprintf(" %s %-30s %s  (%ds)\n",
					cursor, acc.DisplayName(),
					codeStyle.Render(formattedCode), remaining))
			}
		}
	}

	// Message
	if m.message != "" {
		s.WriteString("\n" + m.message + "\n")
	}

	// Help
	helpStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("240"))
	s.WriteString("\n" + helpStyle.Render("[↑↓] Navigate  [Enter] Copy  [q] Quit"))

	return s.String()
}

func tickCmd() tea.Cmd {
	return tea.Tick(time.Second, func(t time.Time) tea.Msg {
		return tickMsg(t)
	})
}
