package account

import (
	"encoding/base32"
	"fmt"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
)

// Account represents a single MFA account
type Account struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Issuer    string    `json:"issuer"`
	Secret    string    `json:"secret"`
	Tag       string    `json:"tag"`
	Algorithm string    `json:"algorithm"`
	Digits    int       `json:"digits"`
	Period    int       `json:"period"`
	CreatedAt time.Time `json:"createdAt"`
}

// Storage represents the encrypted storage structure
type Storage struct {
	Version  string     `json:"version"`
	Accounts []*Account `json:"accounts"`
}

// NewAccount creates a new account with default values
func NewAccount(name, issuer, secret, tag string) (*Account, error) {
	// Validate secret is valid Base32
	secret = strings.ToUpper(strings.ReplaceAll(secret, " ", ""))

	// Add padding if missing (Base32 requires padding to be multiple of 8)
	if len(secret)%8 != 0 {
		secret = secret + strings.Repeat("=", 8-len(secret)%8)
	}

	if _, err := base32.StdEncoding.DecodeString(secret); err != nil {
		return nil, fmt.Errorf("invalid Base32 secret: %w", err)
	}

	return &Account{
		ID:        uuid.New().String(),
		Name:      name,
		Issuer:    issuer,
		Secret:    secret,
		Tag:       tag,
		Algorithm: "SHA1",
		Digits:    6,
		Period:    30,
		CreatedAt: time.Now(),
	}, nil
}

// ParseOTPAuthURL parses an otpauth:// URL and returns an Account
func ParseOTPAuthURL(urlStr string) (*Account, error) {
	u, err := url.Parse(urlStr)
	if err != nil {
		return nil, fmt.Errorf("invalid URL: %w", err)
	}

	if u.Scheme != "otpauth" {
		return nil, fmt.Errorf("invalid scheme: expected otpauth, got %s", u.Scheme)
	}

	if u.Host != "totp" {
		return nil, fmt.Errorf("only TOTP is supported, got %s", u.Host)
	}

	// Parse account name and issuer from path
	path := strings.TrimPrefix(u.Path, "/")
	parts := strings.SplitN(path, ":", 2)

	var issuer, name string
	if len(parts) == 2 {
		issuer = parts[0]
		name = parts[1]
	} else {
		name = parts[0]
	}

	// Parse query parameters
	query := u.Query()
	secret := query.Get("secret")
	if secret == "" {
		return nil, fmt.Errorf("missing secret parameter")
	}

	// Override issuer if provided in query
	if queryIssuer := query.Get("issuer"); queryIssuer != "" {
		issuer = queryIssuer
	}

	algorithm := query.Get("algorithm")
	if algorithm == "" {
		algorithm = "SHA1"
	}

	digits := 6
	if d := query.Get("digits"); d != "" {
		if parsed, err := strconv.Atoi(d); err == nil {
			digits = parsed
		}
	}

	period := 30
	if p := query.Get("period"); p != "" {
		if parsed, err := strconv.Atoi(p); err == nil {
			period = parsed
		}
	}

	// Validate secret
	secret = strings.ToUpper(strings.ReplaceAll(secret, " ", ""))

	// Add padding if missing (Base32 requires padding to be multiple of 8)
	if len(secret)%8 != 0 {
		secret = secret + strings.Repeat("=", 8-len(secret)%8)
	}

	if _, err := base32.StdEncoding.DecodeString(secret); err != nil {
		return nil, fmt.Errorf("invalid Base32 secret: %w", err)
	}

	return &Account{
		ID:        uuid.New().String(),
		Name:      name,
		Issuer:    issuer,
		Secret:    secret,
		Tag:       "",
		Algorithm: algorithm,
		Digits:    digits,
		Period:    period,
		CreatedAt: time.Now(),
	}, nil
}

// ToOTPAuthURL converts an account to otpauth:// URL format
func (a *Account) ToOTPAuthURL() string {
	label := a.Name
	if a.Issuer != "" {
		label = url.PathEscape(a.Issuer) + ":" + url.PathEscape(a.Name)
	} else {
		label = url.PathEscape(a.Name)
	}

	u := url.URL{
		Scheme: "otpauth",
		Host:   "totp",
		Path:   "/" + label,
	}

	query := url.Values{}
	query.Set("secret", a.Secret)
	if a.Issuer != "" {
		query.Set("issuer", a.Issuer)
	}
	if a.Algorithm != "SHA1" {
		query.Set("algorithm", a.Algorithm)
	}
	if a.Digits != 6 {
		query.Set("digits", strconv.Itoa(a.Digits))
	}
	if a.Period != 30 {
		query.Set("period", strconv.Itoa(a.Period))
	}

	u.RawQuery = query.Encode()
	return u.String()
}

// DisplayName returns a formatted display name in the format: Name (Issuer) [Tag]
func (a *Account) DisplayName() string {
	issuer := a.Issuer
	if issuer == "" {
		issuer = "n/a"
	}

	display := fmt.Sprintf("%s (%s)", a.Name, issuer)
	if a.Tag != "" {
		display = fmt.Sprintf("%s [%s]", display, a.Tag)
	}
	return display
}

// NewStorage creates a new storage structure
func NewStorage() *Storage {
	return &Storage{
		Version:  "1.0",
		Accounts: []*Account{},
	}
}

// FindByName finds an account by name (case-insensitive)
func (s *Storage) FindByName(name string) *Account {
	lowerName := strings.ToLower(name)
	for _, acc := range s.Accounts {
		if strings.ToLower(acc.Name) == lowerName {
			return acc
		}
	}
	return nil
}

// FindByID finds an account by ID
func (s *Storage) FindByID(id string) *Account {
	for _, acc := range s.Accounts {
		if acc.ID == id {
			return acc
		}
	}
	return nil
}

// Add adds a new account
func (s *Storage) Add(account *Account) error {
	// If account has no tag and a duplicate name exists (also without tag),
	// auto-number it to avoid confusion
	if account.Tag == "" {
		originalName := account.Name
		counter := 2
		for s.hasDuplicateNameWithoutTag(account.Name) {
			account.Name = fmt.Sprintf("%s (%d)", originalName, counter)
			counter++
		}
	}

	s.Accounts = append(s.Accounts, account)
	return nil
}

// hasDuplicateNameWithoutTag checks if an account with the same name and no tag exists
func (s *Storage) hasDuplicateNameWithoutTag(name string) bool {
	for _, acc := range s.Accounts {
		if acc.Tag == "" && strings.EqualFold(acc.Name, name) {
			return true
		}
	}
	return false
}

// Delete removes an account by name
func (s *Storage) Delete(name string) error {
	for i, acc := range s.Accounts {
		if strings.EqualFold(acc.Name, name) {
			s.Accounts = append(s.Accounts[:i], s.Accounts[i+1:]...)
			return nil
		}
	}
	return fmt.Errorf("account %s not found", name)
}

// Update updates an existing account
func (s *Storage) Update(account *Account) error {
	for i, acc := range s.Accounts {
		if acc.ID == account.ID {
			s.Accounts[i] = account
			return nil
		}
	}
	return fmt.Errorf("account with ID %s not found", account.ID)
}

// FilterByTag returns accounts with the specified tag
func (s *Storage) FilterByTag(tag string) []*Account {
	var filtered []*Account
	for _, acc := range s.Accounts {
		if strings.EqualFold(acc.Tag, tag) {
			filtered = append(filtered, acc)
		}
	}
	return filtered
}
