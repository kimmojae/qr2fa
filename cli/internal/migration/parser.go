package migration

import (
	"encoding/base32"
	"encoding/base64"
	"fmt"
	"net/url"
	"strings"

	"google.golang.org/protobuf/proto"

	"github.com/kimmojae/qr2fa/internal/account"
)

// ParseMigrationURL parses a Google Authenticator migration URL
func ParseMigrationURL(urlStr string) ([]*account.Account, error) {
	u, err := url.Parse(urlStr)
	if err != nil {
		return nil, fmt.Errorf("invalid URL: %w", err)
	}

	if u.Scheme != "otpauth-migration" {
		return nil, fmt.Errorf("not a migration URL")
	}

	// Get the data parameter
	data := u.Query().Get("data")
	if data == "" {
		return nil, fmt.Errorf("missing data parameter")
	}

	// Decode base64
	decoded, err := base64.StdEncoding.DecodeString(data)
	if err != nil {
		return nil, fmt.Errorf("failed to decode base64: %w", err)
	}

	// Parse protobuf
	var payload MigrationPayload
	if err := proto.Unmarshal(decoded, &payload); err != nil {
		return nil, fmt.Errorf("failed to parse protobuf: %w", err)
	}

	// Convert to accounts
	var accounts []*account.Account
	for _, otp := range payload.OtpParameters {
		acc, err := convertOtpToAccount(otp)
		if err != nil {
			// Skip invalid entries
			continue
		}
		accounts = append(accounts, acc)
	}

	if len(accounts) == 0 {
		return nil, fmt.Errorf("no valid accounts found in migration data")
	}

	return accounts, nil
}

func convertOtpToAccount(otp *OtpParameters) (*account.Account, error) {
	// Only support TOTP for now
	if otp.Type != OtpType_OTP_TYPE_TOTP {
		return nil, fmt.Errorf("only TOTP is supported")
	}

	// Check if secret is empty
	if len(otp.Secret) == 0 {
		return nil, fmt.Errorf("empty secret")
	}

	// Encode secret as Base32
	secret := base32.StdEncoding.EncodeToString(otp.Secret)
	secret = strings.TrimRight(secret, "=") // Remove padding (will be re-added by NewAccount if needed)

	// Convert algorithm
	algorithm := "SHA1"
	switch otp.Algorithm {
	case Algorithm_ALGORITHM_SHA1:
		algorithm = "SHA1"
	case Algorithm_ALGORITHM_SHA256:
		algorithm = "SHA256"
	case Algorithm_ALGORITHM_SHA512:
		algorithm = "SHA512"
	case Algorithm_ALGORITHM_MD5:
		algorithm = "MD5"
	}

	// Convert digits
	digits := 6
	switch otp.Digits {
	case DigitCount_DIGIT_COUNT_SIX:
		digits = 6
	case DigitCount_DIGIT_COUNT_EIGHT:
		digits = 8
	}

	// Create account
	acc, err := account.NewAccount(otp.Name, otp.Issuer, secret, "")
	if err != nil {
		return nil, err
	}

	acc.Algorithm = algorithm
	acc.Digits = digits

	return acc, nil
}
