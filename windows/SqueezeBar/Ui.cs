using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace SqueezeBar;

/// <summary>Small builders so rows made in code share one look.</summary>
static class Ui
{
    /// <summary>The Mac app's accent presets, same RGB values.</summary>
    public static readonly (string Name, Color Color)[] AccentPresets =
    [
        ("Blue", Color.FromArgb(255, 26, 128, 255)), ("Purple", Color.FromArgb(255, 166, 82, 224)), ("Pink", Color.FromArgb(255, 250, 82, 148)),
        ("Red", Color.FromArgb(255, 242, 71, 71)), ("Orange", Color.FromArgb(255, 250, 140, 46)), ("Yellow", Color.FromArgb(255, 250, 199, 31)),
        ("Green", Color.FromArgb(255, 82, 209, 107)), ("Graphite", Color.FromArgb(255, 148, 153, 163)),
    ];

    public static Color Accent { get; private set; } = AccentPresets[0].Color;

    /// <summary>Text on top of the accent: dark on light accents such as yellow.</summary>
    public static Brush OnAccent => new SolidColorBrush(
        (Accent.R * 299 + Accent.G * 587 + Accent.B * 114) / 1000 > 170 ? Color.FromArgb(255, 20, 20, 22) : Microsoft.UI.Colors.White);

    public static bool TryParseHex(string hex, out Color color)
    {
        hex = hex.Trim().TrimStart('#');
        color = default;
        if (hex.Length != 6 || !int.TryParse(hex, System.Globalization.NumberStyles.HexNumber, null, out int rgb)) return false;
        color = Color.FromArgb(255, (byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb);
        return true;
    }

    public static void SetAccent(AppPreferences prefs)
    {
        var preset = Array.Find(AccentPresets, a => a.Name == prefs.Accent);
        Accent = prefs.Accent == "Custom" && TryParseHex(prefs.CustomAccentHex, out var custom) ? custom
            : preset.Name is null ? AccentPresets[0].Color : preset.Color;
    }
    public static Brush Secondary => (Brush)Application.Current.Resources["Secondary"];
    public static Brush AccentBrush => new SolidColorBrush(Accent);
    static Style Plain => (Style)Application.Current.Resources["Plain"];

    public static FontIcon Icon(string glyph, double size, Brush? brush = null)
    {
        var icon = new FontIcon { FontFamily = (FontFamily)Application.Current.Resources["Icons"], Glyph = glyph, FontSize = size };
        if (brush is not null) icon.Foreground = brush;
        return icon;
    }

    /// <summary>A row of capsule choices with one selected, the Windows take on the Mac app's pill glider.</summary>
    public sealed class PillBar<T>
    {
        readonly List<(T Value, Button Button)> _pills = [];
        public Grid View { get; } = new() { ColumnSpacing = 4 };

        public PillBar(IReadOnlyList<(T Value, string Label)> options, Func<T, bool> isSelected, Action<T> onPick)
        {
            foreach (var (value, label) in options)
            {
                // Width follows label length so "Visually Lossless" and "2 MB" both fit.
                View.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(label.Length + 4, GridUnitType.Star) });
                var text = new TextBlock { Text = label, FontSize = 11, TextTrimming = TextTrimming.CharacterEllipsis };
                var button = new Button
                {
                    Style = Plain, Content = text, MinHeight = 26, CornerRadius = new CornerRadius(13), Padding = new Thickness(4, 0, 4, 0),
                    HorizontalAlignment = HorizontalAlignment.Stretch, BorderThickness = new Thickness(1),
                };
                AutomationProperties.SetName(button, label);
                button.Click += (_, _) => { onPick(value); Select(isSelected); };
                Grid.SetColumn(button, _pills.Count);
                View.Children.Add(button);
                _pills.Add((value, button));
            }
            Select(isSelected);
        }

        public void Select(Func<T, bool> isSelected)
        {
            foreach (var (value, button) in _pills)
            {
                bool selected = isSelected(value);
                button.Background = new SolidColorBrush(selected ? Accent : Color.FromArgb(15, 255, 255, 255));
                button.BorderBrush = new SolidColorBrush(selected ? Color.FromArgb(70, 255, 255, 255) : Color.FromArgb(18, 255, 255, 255));
                button.Foreground = selected ? OnAccent : Secondary;
                button.FontWeight = selected ? Microsoft.UI.Text.FontWeights.SemiBold : Microsoft.UI.Text.FontWeights.Medium;
            }
        }
    }

    public static TextBlock Text(string text, double size, bool semibold = false, bool secondary = false)
    {
        var block = new TextBlock { Text = text, FontSize = size, VerticalAlignment = VerticalAlignment.Center };
        if (semibold) block.FontWeight = Microsoft.UI.Text.FontWeights.SemiBold;
        if (secondary) block.Foreground = Secondary;
        return block;
    }

    public static Border Card(UIElement child) => new()
    {
        Child = child,
        CornerRadius = new CornerRadius(10),
        Padding = new Thickness(12, 10, 12, 10),
        Background = new SolidColorBrush(Color.FromArgb(10, 255, 255, 255)),
        BorderBrush = new SolidColorBrush(Color.FromArgb(15, 255, 255, 255)),
        BorderThickness = new Thickness(1),
    };

    public static Button IconButton(string glyph, string label)
    {
        var button = new Button
        {
            Style = (Style)Application.Current.Resources["Plain"],
            Width = 24, Height = 24, CornerRadius = new CornerRadius(12), VerticalAlignment = VerticalAlignment.Center,
            Content = new FontIcon { FontFamily = (FontFamily)Application.Current.Resources["Icons"], Glyph = glyph, FontSize = 10, Foreground = Secondary },
        };
        AutomationProperties.SetName(button, label);
        ToolTipService.SetToolTip(button, label);
        return button;
    }

    /// <summary>Switch whose "on" colour follows the app accent instead of the Windows system accent.</summary>
    public static ToggleSwitch Toggle(bool value, Action<bool> set, string? name = null)
    {
        var toggle = new ToggleSwitch { IsOn = value, OnContent = null, OffContent = null, MinWidth = 0, Margin = new Thickness(0, 0, -8, 0), VerticalAlignment = VerticalAlignment.Center };
        foreach (var key in new[] { "ToggleSwitchFillOn", "ToggleSwitchFillOnPointerOver", "ToggleSwitchFillOnPressed", "ToggleSwitchStrokeOn", "ToggleSwitchStrokeOnPointerOver", "ToggleSwitchStrokeOnPressed" })
            toggle.Resources[key] = AccentBrush;
        foreach (var key in new[] { "ToggleSwitchKnobFillOn", "ToggleSwitchKnobFillOnPointerOver", "ToggleSwitchKnobFillOnPressed" })
            toggle.Resources[key] = OnAccent;
        if (name is not null) AutomationProperties.SetName(toggle, name);
        toggle.Toggled += (_, _) => set(toggle.IsOn);
        return toggle;
    }

    public static string Bytes(long bytes) => bytes switch
    {
        >= 1L << 30 => $"{bytes / (double)(1L << 30):0.##} GB",
        >= 1L << 20 => $"{bytes / (double)(1L << 20):0.#} MB",
        >= 1L << 10 => $"{bytes / (double)(1L << 10):0} KB",
        _ => $"{bytes} bytes",
    };
}
