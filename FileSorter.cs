using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Windows.Forms;
using System.Xml.Serialization;

namespace FileSorter
{
    static class Program
    {
        [STAThread]
        static void Main()
        {
            try 
            {
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                
                // Prevent multiple instances
                using (var mutex = new System.Threading.Mutex(false, "FileSorterAppMutex"))
                {
                    if (!mutex.WaitOne(0, false))
                    {
                        MessageBox.Show("Sortify is already running.", "Sortify", MessageBoxButtons.OK, MessageBoxIcon.Information);
                        return;
                    }
                    
                    Application.Run(new FileSorterContext());
                }
            }
            catch (Exception ex)
            {
                File.WriteAllText("crash.txt", ex.ToString());
                MessageBox.Show(ex.Message, "Sortify Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }

    // --- Configuration ---

    public class SortingRule
    {
        public string Extension { get; set; } // e.g., ".pdf"
        public string FolderName { get; set; } // e.g., "PDFs"
    }

    public class AppConfig
    {
        public bool IsEnabled { get; set; }
        public List<SortingRule> Rules { get; set; }

        public AppConfig()
        {
            IsEnabled = true;
            Rules = new List<SortingRule>();
        }

        public static AppConfig Default()
        {
            var config = new AppConfig();
            config.Rules.Add(new SortingRule { Extension = ".pdf", FolderName = "Documents" });
            config.Rules.Add(new SortingRule { Extension = ".docx", FolderName = "Documents" });
            config.Rules.Add(new SortingRule { Extension = ".doc", FolderName = "Documents" });
            config.Rules.Add(new SortingRule { Extension = ".txt", FolderName = "Documents" });
            config.Rules.Add(new SortingRule { Extension = ".jpg", FolderName = "Images" });
            config.Rules.Add(new SortingRule { Extension = ".png", FolderName = "Images" });
            config.Rules.Add(new SortingRule { Extension = ".jpeg", FolderName = "Images" });
            config.Rules.Add(new SortingRule { Extension = ".gif", FolderName = "Images" });
            config.Rules.Add(new SortingRule { Extension = ".zip", FolderName = "Archives" });
            config.Rules.Add(new SortingRule { Extension = ".rar", FolderName = "Archives" });
            config.Rules.Add(new SortingRule { Extension = ".exe", FolderName = "Executables" });
            config.Rules.Add(new SortingRule { Extension = ".msi", FolderName = "Executables" });
            return config;
        }

        public static void Save(AppConfig config, string path)
        {
            XmlSerializer serializer = new XmlSerializer(typeof(AppConfig));
            using (TextWriter writer = new StreamWriter(path))
            {
                serializer.Serialize(writer, config);
            }
        }

        public static AppConfig Load(string path)
        {
            if (!File.Exists(path)) return Default();
            
            try
            {
                XmlSerializer serializer = new XmlSerializer(typeof(AppConfig));
                using (TextReader reader = new StreamReader(path))
                {
                    return (AppConfig)serializer.Deserialize(reader);
                }
            }
            catch
            {
                return Default();
            }
        }
    }

    // --- Core Logic ---

    public class SorterService : IDisposable
    {
        private FileSystemWatcher _watcher;
        private string _downloadsPath;
        private AppConfig _config;
        private string _configPath;

        public SorterService()
        {
            _downloadsPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
            _configPath = Path.Combine(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location), "config.xml");
            _config = AppConfig.Load(_configPath);

            InitializeWatcher();
        }

        public AppConfig Config { get { return _config; } }

        public void SaveConfig()
        {
            AppConfig.Save(_config, _configPath);
            UpdateWatcherState();
        }

        private void InitializeWatcher()
        {
            _watcher = new FileSystemWatcher(_downloadsPath);
            _watcher.NotifyFilter = NotifyFilters.FileName | NotifyFilters.CreationTime;
            _watcher.Created += OnFileCreated;
            _watcher.Renamed += OnFileRenamed;
            
            UpdateWatcherState();
        }

        private void UpdateWatcherState()
        {
            _watcher.EnableRaisingEvents = _config.IsEnabled;
        }

        private void OnFileRenamed(object sender, RenamedEventArgs e)
        {
            ProcessFile(e.FullPath);
        }

        private void OnFileCreated(object sender, FileSystemEventArgs e)
        {
            ProcessFile(e.FullPath);
        }

        private void ProcessFile(string filePath)
        {
            if (!File.Exists(filePath)) return;

            string ext = Path.GetExtension(filePath).ToLower();
            SortingRule rule = null;
            foreach (var r in _config.Rules)
            {
                if (r.Extension.ToLower() == ext)
                {
                    rule = r;
                    break;
                }
            }

            if (rule != null)
            {
                try
                {
                    string targetFolder = Path.Combine(_downloadsPath, rule.FolderName);
                    if (!Directory.Exists(targetFolder))
                    {
                        Directory.CreateDirectory(targetFolder);
                    }

                    string fileName = Path.GetFileName(filePath);
                    string targetPath = Path.Combine(targetFolder, fileName);

                    // Handle duplicates
                    int count = 1;
                    string fileNameWithoutExt = Path.GetFileNameWithoutExtension(fileName);
                    while (File.Exists(targetPath))
                    {
                        string tempName = string.Format("{0} ({1}){2}", fileNameWithoutExt, count, ext);
                        targetPath = Path.Combine(targetFolder, tempName);
                        count++;
                    }

                    // A brief wait to ensure file handles are released (common issue with downloads)
                    System.Threading.Thread.Sleep(500); 
                    
                    try 
                    {
                        File.Move(filePath, targetPath);
                    }
                    catch (IOException)
                    {
                        // File might be locked
                    }
                }
                catch (Exception ex)
                {
                    // Log error?
                    System.Diagnostics.Debug.WriteLine(string.Format("Error moving file: {0}", ex.Message));
                }
            }
        }

        public void Dispose()
        {
            if (_watcher != null) _watcher.Dispose();
        }
    }

    // --- UI ---

    public class FileSorterContext : ApplicationContext
    {
        private NotifyIcon _notifyIcon;
        private SorterService _service;
        private SettingsForm _settingsForm;

        public FileSorterContext()
        {
            _service = new SorterService();
            
            _notifyIcon = new NotifyIcon();
            // Use a standard system icon if we don't have a resource
            _notifyIcon.Icon = SystemIcons.Application; 
            _notifyIcon.Text = "Sortify";
            _notifyIcon.Visible = true;

            ContextMenu menu = new ContextMenu();
            menu.MenuItems.Add(new MenuItem("Open Downloads", new EventHandler(OpenDownloads)));
            menu.MenuItems.Add(new MenuItem("-"));
            menu.MenuItems.Add(new MenuItem("Settings...", new EventHandler(OpenSettings)));
            menu.MenuItems.Add(new MenuItem("Exit", new EventHandler(Exit)));
            
            _notifyIcon.ContextMenu = menu;
            _notifyIcon.DoubleClick += new EventHandler(OpenSettings);
        }

        private void OpenDownloads(object sender, EventArgs e)
        {
             System.Diagnostics.Process.Start("explorer", Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads"));
        }

        private void OpenSettings(object sender, EventArgs e)
        {
            if (_settingsForm == null || _settingsForm.IsDisposed)
            {
                _settingsForm = new SettingsForm(_service);
                _settingsForm.Show();
            }
            else
            {
                _settingsForm.BringToFront();
            }
        }

        private void Exit(object sender, EventArgs e)
        {
            _notifyIcon.Visible = false;
            _service.Dispose();
            Application.Exit();
        }
    }

    public class SettingsForm : Form
    {
        private SorterService _service;
        private DataGridView _grid;
        private CheckBox _enableCheck;
        private Button _saveButton;
        private Button _cancelButton;

        public SettingsForm(SorterService service)
        {
            _service = service;
            InitializeComponent();
            LoadSettings();
        }

        private void InitializeComponent()
        {
            this.Text = "Sortify Settings";
            this.Size = new Size(400, 500);
            this.StartPosition = FormStartPosition.CenterScreen;
            this.FormBorderStyle = FormBorderStyle.FixedSingle;
            this.MaximizeBox = false;

            _enableCheck = new CheckBox();
            _enableCheck.Text = "Enable Custom Sorting";
            _enableCheck.Location = new Point(12, 12);
            _enableCheck.AutoSize = true;
            this.Controls.Add(_enableCheck);

            Label lbl = new Label();
            lbl.Text = "Sorting Rules (Extension -> Folder Name):";
            lbl.Location = new Point(12, 40);
            lbl.AutoSize = true;
            this.Controls.Add(lbl);

            _grid = new DataGridView();
            _grid.Location = new Point(12, 60);
            _grid.Size = new Size(360, 350);
            _grid.ColumnCount = 2;
            _grid.Columns[0].Name = "Extension";
            _grid.Columns[1].Name = "Folder";
            _grid.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;
            this.Controls.Add(_grid);

            _saveButton = new Button();
            _saveButton.Text = "Save";
            _saveButton.Location = new Point(216, 420);
            _saveButton.Click += new EventHandler(Save_Click);
            this.Controls.Add(_saveButton);

            _cancelButton = new Button();
            _cancelButton.Text = "Cancel";
            _cancelButton.Location = new Point(297, 420);
            _cancelButton.Click += new EventHandler(Cancel_Click);
            this.Controls.Add(_cancelButton);
        }

        private void Cancel_Click(object sender, EventArgs e)
        {
            this.Close();
        }

        private void LoadSettings()
        {
            _enableCheck.Checked = _service.Config.IsEnabled;
            _grid.Rows.Clear();
            foreach (var rule in _service.Config.Rules)
            {
                _grid.Rows.Add(rule.Extension, rule.FolderName);
            }
        }

        private void Save_Click(object sender, EventArgs e)
        {
            _service.Config.IsEnabled = _enableCheck.Checked;
            _service.Config.Rules.Clear();

            foreach (DataGridViewRow row in _grid.Rows)
            {
                if (row.IsNewRow) continue;
                
                object extObj = row.Cells[0].Value;
                object folderObj = row.Cells[1].Value;

                string ext = extObj != null ? extObj.ToString() : null;
                string folder = folderObj != null ? folderObj.ToString() : null;

                if (!string.IsNullOrWhiteSpace(ext) && !string.IsNullOrWhiteSpace(folder))
                {
                    if (!ext.StartsWith(".")) ext = "." + ext;
                    _service.Config.Rules.Add(new SortingRule { Extension = ext, FolderName = folder });
                }
            }

            _service.SaveConfig();
            this.Close();
        }
    }
}

