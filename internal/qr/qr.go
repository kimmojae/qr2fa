package qr

import (
	"fmt"
	"image"
	_ "image/jpeg"
	_ "image/png"
	"os"
	"os/exec"

	"github.com/makiuchi-d/gozxing"
	"github.com/makiuchi-d/gozxing/qrcode"
	qrterminal "github.com/mdp/qrterminal/v3"
	goqrcode "github.com/skip2/go-qrcode"
)

// DecodeFromFile decodes a QR code from an image file
func DecodeFromFile(filename string) (string, error) {
	// Open the image file
	file, err := os.Open(filename)
	if err != nil {
		return "", fmt.Errorf("failed to open file: %w", err)
	}
	defer file.Close()

	// Decode the image
	img, _, err := image.Decode(file)
	if err != nil {
		return "", fmt.Errorf("failed to decode image: %w", err)
	}

	// Prepare BinaryBitmap
	bmp, err := gozxing.NewBinaryBitmapFromImage(img)
	if err != nil {
		return "", fmt.Errorf("failed to create binary bitmap: %w", err)
	}

	// Decode QR code
	reader := qrcode.NewQRCodeReader()
	result, err := reader.Decode(bmp, nil)
	if err != nil {
		return "", fmt.Errorf("failed to decode QR code: %w", err)
	}

	return result.GetText(), nil
}

// CaptureFromScreen captures a QR code from screen (macOS only)
func CaptureFromScreen() (string, error) {
	// Create temporary file
	tmpFile, err := os.CreateTemp("", "mfa-qr-*.png")
	if err != nil {
		return "", fmt.Errorf("failed to create temp file: %w", err)
	}
	tmpPath := tmpFile.Name()
	tmpFile.Close()
	defer os.Remove(tmpPath)

	// Use macOS screencapture to select area
	// -d: display errors graphically (shows system permission dialog if needed)
	// -i: interactive mode (select area with mouse)
	cmd := exec.Command("screencapture", "-d", "-i", tmpPath)

	// Capture stdout/stderr for debugging
	output, err := cmd.CombinedOutput()
	if err != nil {
		// Check if file was created (if not, it was cancelled)
		if stat, statErr := os.Stat(tmpPath); statErr != nil || stat.Size() == 0 {
			return "", fmt.Errorf("screen capture was cancelled (ESC pressed)")
		}
		return "", fmt.Errorf("screen capture failed: %w\nOutput: %s", err, string(output))
	}

	// Check if file exists and has content
	stat, err := os.Stat(tmpPath)
	if err != nil || stat.Size() == 0 {
		return "", fmt.Errorf("screen capture was cancelled or produced empty file")
	}

	// Decode the captured image
	return DecodeFromFile(tmpPath)
}

// GenerateTerminal generates and prints a QR code to the terminal
func GenerateTerminal(content string) error {
	// Use simple half-block rendering for compact, clean QR codes
	// Level L = lowest error correction = smallest size
	qrterminal.GenerateHalfBlock(content, qrterminal.L, os.Stdout)
	return nil
}

// GeneratePNG generates a QR code and saves it as a PNG file
func GeneratePNG(content string, filename string) error {
	err := goqrcode.WriteFile(content, goqrcode.Medium, 256, filename)
	if err != nil {
		return fmt.Errorf("failed to generate QR code: %w", err)
	}
	return nil
}

// GeneratePNGWithSize generates a QR code with specified size
func GeneratePNGWithSize(content string, filename string, size int) error {
	err := goqrcode.WriteFile(content, goqrcode.Low, size, filename)
	if err != nil {
		return fmt.Errorf("failed to generate QR code: %w", err)
	}
	return nil
}
