package main

import (
	"image/color"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/theme"
)

// kazumiTheme 是参考 Kazumi 的 Material 3 深色配色。
// 只覆盖常用色，其余交给 Fyne 默认深色主题，避免与不同 fyne 版本冲突。
type kazumiTheme struct {
	fyne.Theme
}

func newKazumiTheme() fyne.Theme {
	return &kazumiTheme{Theme: theme.DarkTheme()}
}

func (k *kazumiTheme) Color(name fyne.ThemeColorName, _ fyne.ThemeVariant) color.Color {
	switch name {
	case theme.ColorNameBackground:
		return color.NRGBA{R: 0x12, G: 0x14, B: 0x18, A: 0xff}
	case theme.ColorNameButton, theme.ColorNameInputBackground:
		return color.NRGBA{R: 0x1E, G: 0x22, B: 0x2A, A: 0xff}
	case theme.ColorNamePrimary, theme.ColorNameFocus:
		return color.NRGBA{R: 0x8A, G: 0xB4, B: 0xF8, A: 0xff}
	case theme.ColorNameHover:
		return color.NRGBA{R: 0x2A, G: 0x30, B: 0x3A, A: 0xff}
	case theme.ColorNameSeparator:
		return color.NRGBA{R: 0x33, G: 0x38, B: 0x42, A: 0xff}
	case theme.ColorNamePlaceHolder:
		return color.NRGBA{R: 0x8A, G: 0x91, B: 0x9E, A: 0xff}
	default:
		return k.Theme.Color(name, theme.VariantDark)
	}
}
