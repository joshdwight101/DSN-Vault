<#
.SYNOPSIS
    DSN-Vault: Universal ODBC Backup & Deployment Tool (MVP)
.DESCRIPTION
    A single-script utility featuring a native C# GUI to completely back up, 
    organize, and restore 32-bit and 64-bit ODBC connections on Windows 11.
#>

# Mandatory Elevation Guard check within PowerShell host
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "Elevated access privileges required. Please execute this script within an Administrator PowerShell instance."
    Read-Host "Press Enter to exit..."
    Exit
}

# Ensure the backup directory exists relative to the script location
$BackupDir = Join-Path -Path $PSScriptRoot -ChildPath "ODBC Backups"
if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir | Out-Null
}

# C# Code Definition for the SysAdmin GUI and Registry Logic
$CSharpCode = @"
using System;
using System.IO;
using System.Xml;
using System.Windows.Forms;
using System.Drawing;
using System.Collections.Generic;
using Microsoft.Win32;

namespace DSNVault
{
    public class DsnItem
    {
        public string Name { get; set; }
        public bool IsSystem { get; set; }
        public override string ToString() {
            return (IsSystem ? "[System] " : "[User]   ") + Name;
        }
    }

    public class VaultEngine
    {
        public static List<DsnItem> GetAvailableDSNs(bool is64Bit)
        {
            List<DsnItem> list = new List<DsnItem>();
            string sysPath = is64Bit ? @"SOFTWARE\ODBC\ODBC.INI\ODBC Data Sources" : @"SOFTWARE\WOW6432Node\ODBC\ODBC.INI\ODBC Data Sources";
            
            using (RegistryKey sysKey = Registry.LocalMachine.OpenSubKey(sysPath))
            {
                if (sysKey != null) {
                    foreach (string val in sysKey.GetValueNames()) {
                        list.Add(new DsnItem { Name = val, IsSystem = true });
                    }
                }
            }
            
            using (RegistryKey usrKey = Registry.CurrentUser.OpenSubKey(@"Software\ODBC\ODBC.INI\ODBC Data Sources"))
            {
                if (usrKey != null) {
                    foreach (string val in usrKey.GetValueNames()) {
                        list.Add(new DsnItem { Name = val, IsSystem = false });
                    }
                }
            }
            return list;
        }

        public static void CreateBackup(string customName, string targetPath, bool is64Bit, List<DsnItem> selectedDsns, Action<string> logger)
        {
            string timeStamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
            
            // Enforce filesystem sanitization as per spec
            string cleanName = customName.Replace(" ", "_")
                                         .Replace("/", "-")
                                         .Replace("\\", "-")
                                         .Replace(":", "-")
                                         .Replace("*", "-")
                                         .Replace("?", "-")
                                         .Replace("\"", "-")
                                         .Replace("<", "-")
                                         .Replace(">", "-")
                                         .Replace("|", "-");

            string arch = is64Bit ? "64bit" : "32bit";
            string fileName = string.Format("ODBC_Backup_{0}_{1}_{2}.xml", timeStamp, arch, cleanName);
            string fullPath = Path.Combine(targetPath, fileName);

            if (logger != null) logger(string.Format("Initializing {0} backup: {1}", arch, cleanName));
            if (logger != null) logger("Target path: " + fullPath);

            using (XmlWriter writer = XmlWriter.Create(fullPath, new XmlWriterSettings { Indent = true }))
            {
                writer.WriteStartElement("ODBCBackup");
                writer.WriteAttributeString("Timestamp", timeStamp);
                writer.WriteAttributeString("Label", customName);
                writer.WriteAttributeString("Architecture", arch);

                List<string> sysDsns = new List<string>();
                List<string> usrDsns = new List<string>();
                foreach(var d in selectedDsns) {
                    if (d.IsSystem) sysDsns.Add(d.Name);
                    else usrDsns.Add(d.Name);
                }

                if (logger != null) logger(string.Format("Found {0} System DSNs and {1} User DSNs to process.", sysDsns.Count, usrDsns.Count));

                if (sysDsns.Count > 0)
                {
                    string hklmPath = is64Bit ? @"SOFTWARE\ODBC\ODBC.INI" : @"SOFTWARE\WOW6432Node\ODBC\ODBC.INI";
                    writer.WriteStartElement("RegistryHive");
                    writer.WriteAttributeString("Path", @"HKLM\" + hklmPath);
                    
                    if (logger != null) logger("> Exporting HKLM Data Sources Master List...");
                    ExportSpecificSubKey(Registry.LocalMachine, hklmPath, "ODBC Data Sources", writer, true, sysDsns, logger);
                    foreach(string dsn in sysDsns) {
                        if (logger != null) logger("> Exporting System DSN: " + dsn);
                        ExportSpecificSubKey(Registry.LocalMachine, hklmPath, dsn, writer, false, null, logger);
                    }
                    
                    writer.WriteEndElement();

                    // --- TRUE MIRRORING: Export the ODBC Driver Registrations (ODBCINST.INI) ---
                    string instPath = is64Bit ? @"SOFTWARE\ODBC\ODBCINST.INI" : @"SOFTWARE\WOW6432Node\ODBC\ODBCINST.INI";
                    if (logger != null) logger("> Exporting HKLM Driver Registrations (ODBCINST.INI)...");
                    writer.WriteStartElement("RegistryHive");
                    writer.WriteAttributeString("Path", @"HKLM\" + instPath);
                    ExportRegistryKey(Registry.LocalMachine, instPath, writer, logger);
                    writer.WriteEndElement();
                }

                if (usrDsns.Count > 0)
                {
                    writer.WriteStartElement("RegistryHive");
                    writer.WriteAttributeString("Path", @"HKCU\Software\ODBC\ODBC.INI");
                    
                    if (logger != null) logger("> Exporting HKCU Data Sources Master List...");
                    ExportSpecificSubKey(Registry.CurrentUser, @"Software\ODBC\ODBC.INI", "ODBC Data Sources", writer, true, usrDsns, logger);
                    foreach(string dsn in usrDsns) {
                        if (logger != null) logger("> Exporting User DSN: " + dsn);
                        ExportSpecificSubKey(Registry.CurrentUser, @"Software\ODBC\ODBC.INI", dsn, writer, false, null, logger);
                    }
                    
                    writer.WriteEndElement();
                }

                writer.WriteEndElement(); // ODBCBackup
            }
            if (logger != null) logger("Backup complete. Payload safely serialized to XML.");
        }

        private static void WriteRegValue(XmlWriter writer, RegistryKey key, string valName)
        {
            object val = key.GetValue(valName);
            if (val == null) return;
            
            RegistryValueKind kind = key.GetValueKind(valName);
            writer.WriteStartElement("Value");
            writer.WriteAttributeString("Name", valName);
            writer.WriteAttributeString("Type", kind.ToString());

            if (kind == RegistryValueKind.Binary) {
                writer.WriteValue(Convert.ToBase64String((byte[])val));
            } else if (kind == RegistryValueKind.MultiString) {
                writer.WriteValue(string.Join("|||", (string[])val));
            } else {
                writer.WriteValue(Convert.ToString(val));
            }
            writer.WriteEndElement();
        }

        private static void ExportRegistryKey(RegistryKey root, string subKeyPath, XmlWriter writer, Action<string> logger)
        {
            using (RegistryKey key = root.OpenSubKey(subKeyPath))
            {
                if (key == null) return;
                
                foreach (string valueName in key.GetValueNames()) {
                    WriteRegValue(writer, key, valueName);
                }

                foreach (string subKeyName in key.GetSubKeyNames()) {
                    writer.WriteStartElement("SubKey");
                    writer.WriteAttributeString("Name", subKeyName);
                    ExportRegistryKey(root, Path.Combine(subKeyPath, subKeyName), writer, logger);
                    writer.WriteEndElement();
                }
            }
        }

        private static void ExportSpecificSubKey(RegistryKey root, string rootPath, string subKeyName, XmlWriter writer, bool isMasterList, List<string> selectedValues, Action<string> logger)
        {
            using (RegistryKey key = root.OpenSubKey(rootPath + @"\" + subKeyName))
            {
                if (key == null) return;
                
                writer.WriteStartElement("SubKey");
                writer.WriteAttributeString("Name", subKeyName);

                if (isMasterList && selectedValues != null)
                {
                    foreach(string valName in selectedValues) {
                        if (key.GetValue(valName) != null) {
                            WriteRegValue(writer, key, valName);
                        }
                    }
                }
                else
                {
                    foreach (string valueName in key.GetValueNames())
                    {
                        WriteRegValue(writer, key, valueName);
                    }

                    foreach (string childSubKeyName in key.GetSubKeyNames())
                    {
                        ExportSpecificSubKey(root, rootPath + @"\" + subKeyName, childSubKeyName, writer, false, null, logger);
                    }
                }
                writer.WriteEndElement();
            }
        }

        public static void RestoreBackup(string filePath, Action<string> logger)
        {
            if (logger != null) logger("Loading XML payload: " + Path.GetFileName(filePath));
            XmlDocument doc = new XmlDocument();
            doc.Load(filePath);

            XmlNodeList hives = doc.GetElementsByTagName("RegistryHive");
            foreach (XmlNode hive in hives)
            {
                string fullPath = hive.Attributes["Path"].Value;
                if (logger != null) logger("Targeting Hive: " + fullPath);
                RegistryKey root = fullPath.StartsWith("HKLM") ? Registry.LocalMachine : Registry.CurrentUser;
                string relativePath = fullPath.Substring(5);

                ImportRegistryKey(root, relativePath, hive, logger);
            }
            if (logger != null) logger("Deployment completely processed to Registry.");
        }

        private static void ImportRegistryKey(RegistryKey root, string relativePath, XmlNode node, Action<string> logger)
        {
            using (RegistryKey key = root.CreateSubKey(relativePath, RegistryKeyPermissionCheck.ReadWriteSubTree))
            {
                foreach (XmlNode child in node.ChildNodes)
                {
                    if (child.Name == "Value")
                    {
                        string name = child.Attributes["Name"].Value;
                        string typeStr = child.Attributes["Type"].Value;
                        string valueStr = child.InnerText;

                        try {
                            RegistryValueKind kind = (RegistryValueKind)Enum.Parse(typeof(RegistryValueKind), typeStr);
                            
                            // High-Fidelity Type Recreation
                            if (kind == RegistryValueKind.DWord) {
                                key.SetValue(name, int.Parse(valueStr), kind);
                            } else if (kind == RegistryValueKind.QWord) {
                                key.SetValue(name, long.Parse(valueStr), kind);
                            } else if (kind == RegistryValueKind.Binary) {
                                key.SetValue(name, Convert.FromBase64String(valueStr), kind);
                            } else if (kind == RegistryValueKind.MultiString) {
                                key.SetValue(name, valueStr.Split(new string[] { "|||" }, StringSplitOptions.None), kind);
                            } else {
                                key.SetValue(name, valueStr, kind);
                            }
                        } catch {
                            // Safe fallback
                            key.SetValue(name, valueStr, RegistryValueKind.String); 
                        }
                    }
                    else if (child.Name == "SubKey")
                    {
                        string subKeyName = child.Attributes["Name"].Value;
                        if (logger != null) logger("> Writing SubKey: " + subKeyName);
                        ImportRegistryKey(root, Path.Combine(relativePath, subKeyName), child, logger);
                    }
                }
            }
        }
    }

    public class AdminGui : Form
    {
        private TabControl tabCtrl;
        private TabPage page32;
        private TabPage page64;
        
        private TextBox txtName32;
        private TextBox txtName64;
        private ListBox lst32;
        private ListBox lst64;
        private TextBox txtConsole;
        
        private string backupFolder;

        public AdminGui(string folder)
        {
            this.backupFolder = folder;
            InitializeComponent();
            Log("DSN-Vault Initialized. Standing by.");
            RefreshBackupList();
        }

        public void Log(string message)
        {
            if (txtConsole.InvokeRequired) {
                txtConsole.Invoke(new Action<string>(Log), new object[] { message });
                return;
            }
            txtConsole.AppendText(string.Format("[{0}] {1}\r\n", DateTime.Now.ToString("HH:mm:ss"), message));
            txtConsole.SelectionStart = txtConsole.Text.Length;
            txtConsole.ScrollToCaret();
        }

        private void InitializeComponent()
        {
            this.Text = "DSN-Vault // Universal ODBC Admin Tool";
            this.Size = new Size(570, 780); // Increased height to accommodate the console
            this.FormBorderStyle = FormBorderStyle.FixedDialog;
            this.MaximizeBox = false;
            this.StartPosition = FormStartPosition.CenterScreen;
            this.BackColor = Color.FromArgb(243, 243, 243);

            Label lblTitle = new Label() { Text = "ODBC Selective Deployment Vault", Font = new Font("Segoe UI", 12, FontStyle.Bold), Location = new Point(15, 15), Size = new Size(400, 25) };
            
            tabCtrl = new TabControl() { Location = new Point(15, 50), Size = new Size(525, 510), Font = new Font("Segoe UI", 9) };
            
            page64 = new TabPage("64-bit System DSNs");
            page64.BackColor = Color.White;
            
            page32 = new TabPage("32-bit System DSNs");
            page32.BackColor = Color.White;

            PopulateTab(page64, true, out txtName64, out lst64);
            PopulateTab(page32, false, out txtName32, out lst32);

            // Add 64-bit tab first as the default modern selection
            tabCtrl.TabPages.Add(page64);
            tabCtrl.TabPages.Add(page32);

            Label lblConsole = new Label() { Text = "Live Status Console:", Location = new Point(15, 570), Size = new Size(200, 15), Font = new Font("Segoe UI", 9, FontStyle.Bold) };
            txtConsole = new TextBox() { 
                Location = new Point(15, 590), 
                Size = new Size(525, 130), 
                Multiline = true, 
                ReadOnly = true, 
                ScrollBars = ScrollBars.Vertical, 
                Font = new Font("Consolas", 8.5f), 
                BackColor = Color.FromArgb(30, 30, 30), 
                ForeColor = Color.FromArgb(0, 214, 143) 
            };

            this.Controls.Add(lblTitle);
            this.Controls.Add(tabCtrl);
            this.Controls.Add(lblConsole);
            this.Controls.Add(txtConsole);
        }

        private void PopulateTab(TabPage page, bool is64Bit, out TextBox txtName, out ListBox lst)
        {
            Label lblSelect = new Label() { Text = "Select DSNs to Backup:", Location = new Point(15, 15), Size = new Size(200, 15) };
            CheckedListBox chkDsns = new CheckedListBox() { Location = new Point(15, 35), Size = new Size(330, 140), CheckOnClick = true, Font = new Font("Consolas", 9f) };
            
            List<DsnItem> availableDsns = VaultEngine.GetAvailableDSNs(is64Bit);
            foreach(var dsn in availableDsns) {
                chkDsns.Items.Add(dsn, true); // Select all by default
            }

            Button btnToggleAll = new Button() { Text = "Toggle All", Location = new Point(15, 180), Size = new Size(100, 25), FlatStyle = FlatStyle.Flat };
            btnToggleAll.Click += (s, e) => {
                bool allChecked = true;
                for(int i = 0; i < chkDsns.Items.Count; i++) {
                    if (!chkDsns.GetItemChecked(i)) { allChecked = false; break; }
                }
                bool newState = !allChecked;
                for(int i = 0; i < chkDsns.Items.Count; i++) {
                    chkDsns.SetItemChecked(i, newState);
                }
            };

            Label lblInput = new Label() { Text = "Custom Backup Label:", Location = new Point(15, 220), Size = new Size(150, 20) };
            txtName = new TextBox() { Location = new Point(15, 240), Size = new Size(330, 23) };
            
            TextBox capturedTxt = txtName;
            capturedTxt.Text = "e.g., Sage300_Production";
            capturedTxt.ForeColor = Color.Gray;
            capturedTxt.Enter += (s, e) => { 
                if (capturedTxt.Text == "e.g., Sage300_Production") { 
                    capturedTxt.Text = ""; 
                    capturedTxt.ForeColor = Color.Black; 
                } 
            };
            capturedTxt.Leave += (s, e) => { 
                if (string.IsNullOrWhiteSpace(capturedTxt.Text)) { 
                    capturedTxt.Text = "e.g., Sage300_Production"; 
                    capturedTxt.ForeColor = Color.Gray; 
                } 
            };

            Button btnBackup = new Button() { Text = "Capture Backup", Location = new Point(360, 239), Size = new Size(130, 25), Font = new Font("Segoe UI", 9, FontStyle.Bold), BackColor = Color.FromArgb(0, 120, 212), ForeColor = Color.White, FlatStyle = FlatStyle.Flat };
            btnBackup.Click += (s, e) => HandleBackup(is64Bit, capturedTxt, chkDsns);

            Label lblList = new Label() { Text = "Available Backups (" + backupFolder + "):", Location = new Point(15, 285), Size = new Size(500, 20) };
            lst = new ListBox() { Location = new Point(15, 305), Size = new Size(330, 160), Font = new Font("Consolas", 9.5f) };
            
            ListBox capturedLst = lst;
            
            // Build the Right-Click Context Menu for the ListBox
            ContextMenuStrip ctxMenu = new ContextMenuStrip();
            ToolStripMenuItem mnuRestore = new ToolStripMenuItem("Deploy/Restore Backup");
            ToolStripMenuItem mnuDelete = new ToolStripMenuItem("Delete Backup");
            ctxMenu.Items.Add(mnuRestore);
            ctxMenu.Items.Add(mnuDelete);

            // Dynamically select the list item under the cursor on Right-Click
            capturedLst.MouseDown += (s, e) => {
                if (e.Button == MouseButtons.Right) {
                    int index = capturedLst.IndexFromPoint(e.Location);
                    if (index != ListBox.NoMatches) {
                        capturedLst.SelectedIndex = index;
                        ctxMenu.Show(capturedLst, e.Location);
                    }
                }
            };

            mnuRestore.Click += (s, e) => HandleRestore(capturedLst);
            mnuDelete.Click += (s, e) => HandleDelete(capturedLst);

            Button btnRestore = new Button() { Text = "Deploy Selected", Location = new Point(360, 305), Size = new Size(130, 35), Font = new Font("Segoe UI", 9, FontStyle.Bold), BackColor = Color.FromArgb(16, 124, 65), ForeColor = Color.White, FlatStyle = FlatStyle.Flat };
            btnRestore.Click += (s, e) => HandleRestore(capturedLst);

            Button btnRefresh = new Button() { Text = "Refresh List", Location = new Point(360, 350), Size = new Size(130, 25), FlatStyle = FlatStyle.Flat };
            btnRefresh.Click += (s, e) => {
                RefreshBackupList();
                chkDsns.Items.Clear();
                foreach(var dsn in VaultEngine.GetAvailableDSNs(is64Bit)) chkDsns.Items.Add(dsn, true);
            };

            page.Controls.AddRange(new Control[] { lblSelect, chkDsns, btnToggleAll, lblInput, capturedTxt, btnBackup, lblList, capturedLst, btnRestore, btnRefresh });
        }

        private void RefreshBackupList()
        {
            lst32.Items.Clear();
            lst64.Items.Clear();
            if (!Directory.Exists(backupFolder)) return;

            string[] files = Directory.GetFiles(backupFolder, "*.xml");
            foreach (string file in files)
            {
                string fileName = Path.GetFileName(file);
                
                // Automatically filter backups into respective tabs
                if (fileName.Contains("_32bit_")) {
                    lst32.Items.Add(fileName);
                }
                else if (fileName.Contains("_64bit_")) {
                    lst64.Items.Add(fileName);
                }
                else {
                    // Catch-all for legacy backups generated prior to tab implementation
                    lst32.Items.Add(fileName);
                    lst64.Items.Add(fileName);
                }
            }
            Log(string.Format("Refreshed inventory: {0} total backups found.", lst32.Items.Count + lst64.Items.Count));
        }

        private void HandleBackup(bool is64Bit, TextBox txtName, CheckedListBox chkDsns)
        {
            if (chkDsns.CheckedItems.Count == 0) {
                MessageBox.Show("Please select at least one DSN to backup.", "No DSNs Selected", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            List<DsnItem> selectedDsns = new List<DsnItem>();
            foreach(var item in chkDsns.CheckedItems) {
                selectedDsns.Add((DsnItem)item);
            }

            string label = string.IsNullOrWhiteSpace(txtName.Text) || txtName.Text == "e.g., Sage300_Production" ? "GenericBackup" : txtName.Text.Trim();
            try
            {
                VaultEngine.CreateBackup(label, backupFolder, is64Bit, selectedDsns, Log);
                string arch = is64Bit ? "64-bit" : "32-bit";
                Log("SUCCESS: " + arch + " ODBC configurations captured successfully.");
                MessageBox.Show(arch + " ODBC configurations successfully backed up!", "Success", MessageBoxButtons.OK, MessageBoxIcon.Information);
                
                txtName.Text = "e.g., Sage300_Production";
                txtName.ForeColor = Color.Gray;
                
                RefreshBackupList();
            }
            catch (Exception ex)
            {
                Log("ERROR (Backup): " + ex.Message);
                MessageBox.Show("Backup failed: " + ex.Message, "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void HandleRestore(ListBox lst)
        {
            if (lst.SelectedItem == null)
            {
                MessageBox.Show("Please select a backup file from the list first.", "Selection Required", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            string selectedFile = Path.Combine(backupFolder, lst.SelectedItem.ToString());
            
            DialogResult confirm = MessageBox.Show("Are you sure you want to deploy this backup? Existing matching DSNs will be overwritten.", "Confirm Deployment", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            if (confirm == DialogResult.Yes)
            {
                try
                {
                    Log("Initiating deployment for payload: " + lst.SelectedItem.ToString());
                    VaultEngine.RestoreBackup(selectedFile, Log);
                    Log("SUCCESS: ODBC configurations deployed cleanly.");
                    MessageBox.Show("ODBC configurations successfully written to Windows 11 Registry!", "Deployment Complete", MessageBoxButtons.OK, MessageBoxIcon.Information);
                }
                catch (Exception ex)
                {
                    Log("ERROR (Restore): " + ex.Message);
                    MessageBox.Show("Restore failed: " + ex.Message, "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
        }

        private void HandleDelete(ListBox lst)
        {
            if (lst.SelectedItem == null) return;
            
            string selectedFile = Path.Combine(backupFolder, lst.SelectedItem.ToString());
            DialogResult confirm = MessageBox.Show("Are you sure you want to permanently delete this backup file:\n" + lst.SelectedItem.ToString(), "Confirm Deletion", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
            
            if (confirm == DialogResult.Yes)
            {
                try
                {
                    File.Delete(selectedFile);
                    Log("DELETED: Removed backup file " + lst.SelectedItem.ToString());
                    RefreshBackupList();
                }
                catch (Exception ex)
                {
                    Log("ERROR (Delete): " + ex.Message);
                    MessageBox.Show("Delete failed: " + ex.Message, "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
        }
    }
}
"@

# Load Windows Forms dependencies and compile the inline C# framework
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -TypeDefinition $CSharpCode -ReferencedAssemblies "System.Windows.Forms", "System.Drawing", "System.Xml"

# Launch the Application (Swapped to ShowDialog for VS Code / ISE compatibility)
try { [System.Windows.Forms.Application]::EnableVisualStyles() } catch { }
$Form = New-Object DSNVault.AdminGui -ArgumentList $BackupDir
$Form.ShowDialog() | Out-Null
$Form.Dispose()
