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

type viewMode int

const (
	viewFolder viewMode = iota // issuer folders, expand/collapse
	viewGroup                  // issuer headers + accounts listed
	viewFlat                   // flat list, one line per account
)

var viewModeNames = []string{"Folder", "Group", "Flat"}

// listItem represents a row in the TUI (either an issuer header or an account)
type listItem struct {
	isHeader bool
	issuer   string
	account  *account.Account
	expanded bool // only for headers in folder view
}

// Model represents the TUI state
type Model struct {
	storage        *account.Storage
	storageManager *storage.Manager
	accounts       []*account.Account
	filteredAccs   []*account.Account
	items          []listItem // rendered list items
	cursor         int
	searchText     string
	width          int
	height         int
	message        string
	err            error
	mode           viewMode
	expandedGroups map[string]bool // issuer -> expanded state
}

type tickMsg time.Time

var tagColors = map[string]lipgloss.Color{
	"dev":  lipgloss.Color("12"), // Blue
	"prod": lipgloss.Color("9"),  // Red
}

// Run starts the TUI
func Run(st *account.Storage, sm *storage.Manager) error {
	m := &Model{
		storage:        st,
		storageManager: sm,
		accounts:       st.Accounts,
		mode:           viewFolder,
		expandedGroups: make(map[string]bool),
	}

	// Sort accounts by issuer then name
	sort.Slice(m.accounts, func(i, j int) bool {
		if m.accounts[i].Issuer != m.accounts[j].Issuer {
			return strings.ToLower(m.accounts[i].Issuer) < strings.ToLower(m.accounts[j].Issuer)
		}
		return strings.ToLower(m.accounts[i].Name) < strings.ToLower(m.accounts[j].Name)
	})

	m.filteredAccs = m.accounts
	m.buildItems()

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
		m.buildItems()
		return m, tickCmd()
	}
	return m, nil
}

func (m *Model) handleKeyPress(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "ctrl+c", "q":
		return m, tea.Quit
	case "tab":
		m.mode = (m.mode + 1) % 3
		m.cursor = 0
		m.buildItems()
	case "up", "k":
		if m.cursor > 0 {
			m.cursor--
		}
	case "down", "j":
		if m.cursor < len(m.items)-1 {
			m.cursor++
		}
	case "enter", " ":
		if m.cursor < len(m.items) {
			item := m.items[m.cursor]
			if item.isHeader {
				// Toggle expand/collapse in folder view
				if m.mode == viewFolder {
					m.expandedGroups[item.issuer] = !m.expandedGroups[item.issuer]
					m.buildItems()
					// Keep cursor on the header
				}
			} else if item.account != nil {
				code, err := totp.Generate(item.account)
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
		}
	case "backspace":
		if len(m.searchText) > 0 {
			m.searchText = m.searchText[:len(m.searchText)-1]
			m.filterAccounts()
			m.buildItems()
		}
	default:
		if len(msg.Runes) == 1 && msg.Runes[0] >= 32 && msg.Runes[0] <= 126 {
			m.searchText += string(msg.Runes[0])
			m.filterAccounts()
			m.buildItems()
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

// buildItems constructs the list items based on current view mode and filters
func (m *Model) buildItems() {
	m.items = nil

	switch m.mode {
	case viewFolder:
		m.buildFolderItems()
	case viewGroup:
		m.buildGroupItems()
	case viewFlat:
		m.buildFlatItems()
	}

	// Clamp cursor
	if m.cursor >= len(m.items) {
		m.cursor = len(m.items) - 1
	}
	if m.cursor < 0 {
		m.cursor = 0
	}
}

func (m *Model) buildFolderItems() {
	// Group by issuer
	groups := m.groupByIssuer()
	for _, g := range groups {
		issuer := g.issuer
		expanded := m.expandedGroups[issuer]
		m.items = append(m.items, listItem{
			isHeader: true,
			issuer:   issuer,
			expanded: expanded,
		})
		if expanded {
			for _, acc := range g.accounts {
				m.items = append(m.items, listItem{account: acc})
			}
		}
	}
}

func (m *Model) buildGroupItems() {
	groups := m.groupByIssuer()
	for i, g := range groups {
		if i > 0 {
			// Add empty separator
			m.items = append(m.items, listItem{isHeader: true, issuer: g.issuer})
		} else {
			m.items = append(m.items, listItem{isHeader: true, issuer: g.issuer})
		}
		for _, acc := range g.accounts {
			m.items = append(m.items, listItem{account: acc})
		}
	}
}

func (m *Model) buildFlatItems() {
	for _, acc := range m.filteredAccs {
		m.items = append(m.items, listItem{account: acc})
	}
}

type issuerGroup struct {
	issuer   string
	accounts []*account.Account
}

func (m *Model) groupByIssuer() []issuerGroup {
	orderMap := make(map[string][]*account.Account)
	var order []string
	for _, acc := range m.filteredAccs {
		issuer := acc.Issuer
		if issuer == "" {
			issuer = "n/a"
		}
		if _, exists := orderMap[issuer]; !exists {
			order = append(order, issuer)
		}
		orderMap[issuer] = append(orderMap[issuer], acc)
	}

	var groups []issuerGroup
	for _, issuer := range order {
		groups = append(groups, issuerGroup{issuer: issuer, accounts: orderMap[issuer]})
	}
	return groups
}

func (m *Model) View() string {
	var s strings.Builder

	s.WriteString("\n")

	// Title + view mode
	titleStyle := lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("99"))
	dimStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("245"))
	keyStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("252")).Bold(true)
	s.WriteString(titleStyle.Render("QR2FA") + " " + dimStyle.Render("v0.1.0") + "\n\n")

	// Search bar
	s.WriteString(keyStyle.Render("Search:") + " " + m.searchText + "\n\n")

	if len(m.items) == 0 {
		s.WriteString("No accounts found.\n")
	} else {
		issuerStyle := lipgloss.NewStyle().Bold(true)

		for i, item := range m.items {
			isCursor := i == m.cursor

			if item.isHeader {
				// Issuer header
				prefix := " "
				label := item.issuer

				if m.mode == viewFolder {
					if item.expanded {
						prefix = "▼"
					} else {
						prefix = "▶"
					}
					// Count accounts in this group
					count := 0
					for _, acc := range m.filteredAccs {
						issuer := acc.Issuer
						if issuer == "" {
							issuer = "n/a"
						}
						if issuer == item.issuer {
							count++
						}
					}
					label = fmt.Sprintf("%s (%d)", item.issuer, count)
				}

				line := fmt.Sprintf(" %s %s", prefix, label)
				if isCursor {
					s.WriteString(lipgloss.NewStyle().Reverse(true).Render(line) + "\n")
				} else {
					s.WriteString(" " + prefix + " " + issuerStyle.Render(label) + "\n")
				}
			} else {
				// Account row
				acc := item.account
				code, _ := totp.Generate(acc)
				remaining := totp.RemainingSeconds(acc)
				formattedCode := totp.FormatCode(code)

				var codeStyle lipgloss.Style
				if remaining > 12 {
					codeStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("10"))
				} else if remaining > 5 {
					codeStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("11"))
				} else {
					codeStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("9"))
				}

				// Build tag string
				tagStr := ""
				if acc.Tag != "" {
					color, ok := tagColors[acc.Tag]
					if !ok {
						color = lipgloss.Color("14")
					}
					tagRendered := lipgloss.NewStyle().Foreground(color).Render("[" + acc.Tag + "]")
					tagStr = tagRendered + " "
				}

				indent := "    "
				if m.mode == viewFlat {
					indent = " "
					issuer := acc.Issuer
					if issuer == "" {
						issuer = "n/a"
					}
					tagStr = issuer + " " + tagStr
				}

				numStr := fmt.Sprintf("#%-2d", acc.ID)
				numStyle := dimStyle.Render(numStr)

				if isCursor {
					// Plain text for reverse render
					plainTag := ""
					if acc.Tag != "" {
						plainTag = "[" + acc.Tag + "] "
					}
					plainIssuer := ""
					if m.mode == viewFlat {
						issuer := acc.Issuer
						if issuer == "" {
							issuer = "n/a"
						}
						plainIssuer = issuer + " "
					}
					line := fmt.Sprintf("%s▶ %s %s%s%-20s %s  (%ds)", indent, numStr, plainIssuer, plainTag, acc.Name, formattedCode, remaining)
					s.WriteString(lipgloss.NewStyle().Reverse(true).Render(line) + "\n")
				} else {
					s.WriteString(fmt.Sprintf("%s  %s %s%-20s %s  (%ds)\n",
						indent, numStyle, tagStr, acc.Name,
						codeStyle.Render(formattedCode), remaining))
				}
			}
		}
	}

	// Message
	if m.message != "" {
		s.WriteString("\n" + m.message + "\n")
	}

	// Help
	helpKeyStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("252")).Bold(true)
	helpDescStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("245"))

	var helpParts []string
	if m.mode == viewFolder {
		helpParts = []string{
			helpKeyStyle.Render("[↑↓]") + helpDescStyle.Render(" Navigate"),
			helpKeyStyle.Render("[Enter/Space]") + helpDescStyle.Render(" Open/Copy"),
			helpKeyStyle.Render("[Tab]") + helpDescStyle.Render(" View"),
			helpKeyStyle.Render("[q]") + helpDescStyle.Render(" Quit"),
		}
	} else {
		helpParts = []string{
			helpKeyStyle.Render("[↑↓]") + helpDescStyle.Render(" Navigate"),
			helpKeyStyle.Render("[Enter]") + helpDescStyle.Render(" Copy"),
			helpKeyStyle.Render("[Tab]") + helpDescStyle.Render(" View"),
			helpKeyStyle.Render("[q]") + helpDescStyle.Render(" Quit"),
		}
	}
	s.WriteString("\n" + strings.Join(helpParts, "  "))

	return s.String()
}

func tickCmd() tea.Cmd {
	return tea.Tick(time.Second, func(t time.Time) tea.Msg {
		return tickMsg(t)
	})
}
