using System.Diagnostics;

var dir = Path.Combine(AppContext.BaseDirectory, "app");
var exe = Path.Combine(dir, "SqueezeBar.exe");
if (File.Exists(exe)) Process.Start(new ProcessStartInfo(exe) { WorkingDirectory = dir });
