package totp

import (
	"crypto"
	"fmt"
	"time"

	"github.com/kimmojae/qr2fa/internal/account"
	"github.com/pquerna/otp"
	"github.com/pquerna/otp/totp"
)

// Generate generates a TOTP code for an account
func Generate(acc *account.Account) (string, error) {
	return GenerateAtTime(acc, time.Now())
}

// GenerateAtTime generates a TOTP code for an account at a specific time
func GenerateAtTime(acc *account.Account, t time.Time) (string, error) {
	// Parse algorithm
	algorithm := parseAlgorithm(acc.Algorithm)

	// Generate code
	code, err := totp.GenerateCodeCustom(
		acc.Secret,
		t,
		totp.ValidateOpts{
			Period:    uint(acc.Period),
			Skew:      1,
			Digits:    otp.Digits(acc.Digits),
			Algorithm: algorithm,
		},
	)
	if err != nil {
		return "", fmt.Errorf("failed to generate TOTP code: %w", err)
	}

	return code, nil
}

// RemainingSeconds returns the number of seconds until the current code expires
func RemainingSeconds(acc *account.Account) int {
	return RemainingSecondsAtTime(acc, time.Now())
}

// RemainingSecondsAtTime returns the number of seconds until the code expires at a specific time
func RemainingSecondsAtTime(acc *account.Account, t time.Time) int {
	period := acc.Period
	elapsed := int(t.Unix()) % period
	return period - elapsed
}

// FormatCode formats a TOTP code with spacing (e.g., "123456" -> "123 456")
func FormatCode(code string) string {
	if len(code) == 6 {
		return fmt.Sprintf("%s %s", code[:3], code[3:])
	}
	if len(code) == 8 {
		return fmt.Sprintf("%s %s", code[:4], code[4:])
	}
	return code
}

// parseAlgorithm converts algorithm string to crypto.Hash
func parseAlgorithm(algorithm string) otp.Algorithm {
	switch algorithm {
	case "SHA1":
		return otp.AlgorithmSHA1
	case "SHA256":
		return otp.AlgorithmSHA256
	case "SHA512":
		return otp.AlgorithmSHA512
	case "MD5":
		return otp.AlgorithmMD5
	default:
		return otp.AlgorithmSHA1
	}
}

// Validate validates a TOTP code for an account
func Validate(acc *account.Account, code string) bool {
	algorithm := parseAlgorithm(acc.Algorithm)

	valid, err := totp.ValidateCustom(
		code,
		acc.Secret,
		time.Now(),
		totp.ValidateOpts{
			Period:    uint(acc.Period),
			Skew:      1,
			Digits:    otp.Digits(acc.Digits),
			Algorithm: algorithm,
		},
	)

	return err == nil && valid
}

// GetAlgorithmHash returns the crypto.Hash for an algorithm string
func GetAlgorithmHash(algorithm string) crypto.Hash {
	switch algorithm {
	case "SHA1":
		return crypto.SHA1
	case "SHA256":
		return crypto.SHA256
	case "SHA512":
		return crypto.SHA512
	case "MD5":
		return crypto.MD5
	default:
		return crypto.SHA1
	}
}
