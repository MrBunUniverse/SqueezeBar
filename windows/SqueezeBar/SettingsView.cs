using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.UI;

namespace SqueezeBar;

/// <summary>
/// The Settings tab: app behaviour and appearance, in the Mac app's groups. Compression controls live
/// in the Activity tab's format deck. Controls read from and write straight to <see cref="AppState"/>.
/// </summary>
static class SettingsView
{
    public static void Build(StackPanel panel, AppState state, MainWindow window)
    {
        var config = state.Config;
        var prefs = state.Prefs;
        void Rebuild() => Build(panel, state, window);
        panel.Children.Clear();

        // ---- Output
        var output = new List<UIElement>
        {
            Row("Create subfolder for compressed files", Toggle(config.ExportToSubfolder, v => { state.Update(c => c with { ExportToSubfolder = v }); Rebuild(); })),
        };
        if (config.ExportToSubfolder)
            output.Add(Row("Subfolder name", TextField(config.SubfolderName, "Squeezed", v => state.Update(c => c with { SubfolderName = v }))));
        output.Add(Row("Save to folder", FolderChooser(config.CustomOutputFolder, "Next to original", window,
            path => { state.Update(c => c with { CustomOutputFolder = path }); Rebuild(); })));
        output.Add(Row("Output file suffix", TextField(config.Suffix, "_min", v => state.Update(c => c with { Suffix = v }))));
        output.Add(Row("Strip EXIF / metadata", Toggle(config.StripMetadata, v => state.Update(c => c with { StripMetadata = v })), "Removes location and camera info"));
        panel.Children.Add(Section("", "Output", string.IsNullOrEmpty(config.CustomOutputFolder) ? "Next to original" : "Custom folder", output));

        // ---- Input methods
        var input = new List<UIElement>
        {
            Row("Explorer right-click action", Toggle(ExplorerMenu.IsEnabled, ExplorerMenu.Set),
                "Adds \"Squeeze with SqueezeBar\" for files and folders (under \"Show more options\" on Windows 11)"),
            Row("Auto-squeeze watch folder", Toggle(prefs.WatchFolderEnabled, v =>
            {
                state.UpdatePrefs(p => p with { WatchFolderEnabled = v });
                window.RestartWatchFolder();
                Rebuild();
            }), "Compresses new files added to this folder"),
        };
        if (prefs.WatchFolderEnabled)
            input.Add(Row("Folder to watch", FolderChooser(prefs.WatchFolder, "None chosen", window, path =>
            {
                state.UpdatePrefs(p => p with { WatchFolder = path });
                window.RestartWatchFolder();
                Rebuild();
            })));
        panel.Children.Add(Section("", "Input methods", null, input));

        // ---- Completion feedback
        var feedback = new List<UIElement>
        {
            Row("Sound chime on completion", Toggle(prefs.SoundEnabled, v => { state.UpdatePrefs(p => p with { SoundEnabled = v }); Rebuild(); })),
        };
        if (prefs.SoundEnabled)
            feedback.Add(Padded(new Ui.PillBar<string>(Sounds.Themes.Select(t => (t.Name, t.Name)).ToList(), n => state.Prefs.SoundTheme == n, n =>
            {
                state.UpdatePrefs(p => p with { SoundTheme = n });
                Sounds.Play(n); // preview
            }).View));
        panel.Children.Add(Section("", "Completion feedback", prefs.SoundEnabled ? prefs.SoundTheme : "Off", feedback));

        // ---- General
        var reset = new Button { Content = "Reset stats", FontSize = 11, Padding = new Thickness(8, 3, 8, 3), IsEnabled = prefs.TotalBytesSaved > 0 };
        reset.Click += (_, _) =>
        {
            state.UpdatePrefs(p => p with { TotalBytesSaved = 0 });
            window.RefreshHistory();
            Rebuild();
        };
        panel.Children.Add(Section("", "General", null,
        [
            Row("Launch at system startup", Toggle(StartupEntry.IsEnabled, StartupEntry.Set), "Starts quietly in the tray when you sign in"),
            Row("Reset all compression stats", reset, $"Saved {Ui.Bytes(prefs.TotalBytesSaved)} so far"),
        ]));

        // ---- Appearance
        panel.Children.Add(Section("", "Appearance", "Scale, accent color",
        [
            Stacked("Interface scaling", null, new Ui.PillBar<UiScale>(
                [(UiScale.Small, "Small (85%)"), (UiScale.Medium, "Medium (100%)"), (UiScale.Large, "Large (118%)")],
                v => state.Prefs.Scale == v,
                v => { state.UpdatePrefs(p => p with { Scale = v }); window.ApplyAppearance(rebuild: true); }).View),
            Stacked("Accent color", null, AccentPicker(state, window)),
        ]));
    }

    // MARK: - Building blocks

    static StackPanel Section(string icon, string title, string? summary, IReadOnlyList<UIElement> rows)
    {
        var body = new StackPanel();
        for (int i = 0; i < rows.Count; i++)
        {
            if (i > 0) body.Children.Add(new Border { Height = 1, Background = new SolidColorBrush(Color.FromArgb(18, 255, 255, 255)) });
            body.Children.Add(rows[i]);
        }
        var card = Ui.Card(body);
        card.Padding = new Thickness(12, 2, 12, 2);

        var heading = new Grid { Margin = new Thickness(4, 0, 4, 0) };
        heading.Children.Add(new StackPanel
        {
            Orientation = Orientation.Horizontal, Spacing = 6,
            Children = { Ui.Icon(icon, 11, Ui.Secondary), Ui.Text(title, 11, semibold: true, secondary: true) },
        });
        if (summary is not null)
        {
            var note = Ui.Text(summary, 10.5, secondary: true);
            note.HorizontalAlignment = HorizontalAlignment.Right;
            heading.Children.Add(note);
        }
        return new StackPanel { Spacing = 6, Children = { heading, card } };
    }

    static Grid Row(string label, FrameworkElement control, string? detail = null)
    {
        var row = new Grid { MinHeight = 40, ColumnSpacing = 12, Padding = new Thickness(0, detail is null ? 0 : 6, 0, detail is null ? 0 : 6) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var labels = new StackPanel { Spacing = 1, VerticalAlignment = VerticalAlignment.Center, Children = { Ui.Text(label, 12, semibold: true) } };
        if (detail is not null)
        {
            var note = Ui.Text(detail, 10.5, secondary: true);
            note.TextWrapping = TextWrapping.Wrap;
            labels.Children.Add(note);
        }
        row.Children.Add(labels);
        control.VerticalAlignment = VerticalAlignment.Center;
        control.HorizontalAlignment = HorizontalAlignment.Right;
        if (control is not Panel) AutomationProperties.SetName(control, label);
        Grid.SetColumn(control, 1);
        row.Children.Add(control);
        return row;
    }

    /// <summary>A titled block whose control sits underneath the title instead of beside it.</summary>
    static StackPanel Stacked(string title, FrameworkElement? trailing, FrameworkElement content)
    {
        var header = new Grid();
        header.Children.Add(Ui.Text(title, 12, semibold: true));
        if (trailing is not null) { trailing.HorizontalAlignment = HorizontalAlignment.Right; header.Children.Add(trailing); }
        return new StackPanel { Spacing = 8, Padding = new Thickness(0, 10, 0, 10), Children = { header, content } };
    }

    static Border Padded(UIElement child) => new() { Child = child, Padding = new Thickness(0, 8, 0, 10) };

    static ToggleSwitch Toggle(bool value, Action<bool> set) => Ui.Toggle(value, set);

    static TextBox TextField(string value, string placeholder, Action<string> set)
    {
        var box = new TextBox { Text = value, PlaceholderText = placeholder, Width = 130, FontSize = 12 };
        box.TextChanged += (_, _) => set(box.Text);
        return box;
    }

    static StackPanel FolderChooser(string? current, string emptyLabel, MainWindow window, Action<string?> set)
    {
        bool chosen = !string.IsNullOrEmpty(current);
        var label = Ui.Text(chosen ? System.IO.Path.GetFileName(current!.TrimEnd('\\')) is { Length: > 0 } name ? name : current! : emptyLabel, 11, secondary: true);
        label.TextTrimming = TextTrimming.CharacterEllipsis;
        label.MaxWidth = 140;
        if (chosen) ToolTipService.SetToolTip(label, current);
        var choose = new Button { Content = "Choose…", FontSize = 11, Padding = new Thickness(8, 3, 8, 3) };
        AutomationProperties.SetName(choose, "Choose folder");
        choose.Click += async (_, _) => { if (await window.PickFolderAsync() is string path) set(path); };
        var controls = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, Children = { label, choose } };
        if (chosen)
        {
            var clear = Ui.IconButton("", "Clear");
            clear.Click += (_, _) => set(null);
            controls.Children.Add(clear);
        }
        return controls;
    }

    static StackPanel AccentPicker(AppState state, MainWindow window)
    {
        var prefs = state.Prefs;
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        foreach (var (name, color) in Ui.AccentPresets)
        {
            bool selected = prefs.Accent == name;
            var swatch = new Button
            {
                Style = (Style)Application.Current.Resources["Plain"], Width = 26, Height = 26, CornerRadius = new CornerRadius(13),
                BorderThickness = new Thickness(2), BorderBrush = new SolidColorBrush(selected ? Microsoft.UI.Colors.White : Microsoft.UI.Colors.Transparent),
                Content = new Ellipse { Width = 18, Height = 18, Fill = new SolidColorBrush(color) },
            };
            AutomationProperties.SetName(swatch, $"{name} accent");
            ToolTipService.SetToolTip(swatch, name);
            swatch.Click += (_, _) => { state.UpdatePrefs(p => p with { Accent = name }); window.ApplyAppearance(rebuild: true); };
            row.Children.Add(swatch);
        }

        var hex = new TextBox { Text = prefs.CustomAccentHex, PlaceholderText = "HEX", Width = 86, FontSize = 12, MaxLength = 7 };
        AutomationProperties.SetName(hex, "Custom accent HEX code");
        ToolTipService.SetToolTip(hex, "Custom color as a HEX code, for example 1A80FF. Press Enter to apply.");
        if (prefs.Accent == "Custom") hex.BorderBrush = Ui.AccentBrush;
        hex.KeyDown += (_, e) =>
        {
            if (e.Key != Windows.System.VirtualKey.Enter || !Ui.TryParseHex(hex.Text, out Color _)) return;
            state.UpdatePrefs(p => p with { Accent = "Custom", CustomAccentHex = hex.Text.Trim().TrimStart('#').ToUpperInvariant() });
            window.ApplyAppearance(rebuild: true);
        };
        row.Children.Add(hex);
        return row;
    }
}
