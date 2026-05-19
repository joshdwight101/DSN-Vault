# **Changelog**

All notable changes to the DSN-Vault project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),

and this project adheres to Semantic Versioning.

## **\[1.0.0\] \- 2026-05-19**

### **Added**

* **Initial Production Release**.  
* Fully self-contained C\# WinForms GUI executable via a single DSN-Vault.ps1 PowerShell script.  
* TabControl interface separating 64-bit System DSNs and 32-bit System DSNs for isolated operations.  
* Dynamic DSN Discovery Engine displaying available System and User DSNs via a CheckedListBox for selective backing up.  
* **True Mirror Engine**: Backups now include the core ODBCINST.INI driver registry trees to ensure target machines recognize drivers automatically.  
* High-fidelity Registry Type preservation: Binary, DWord, QWord, and MultiString types are now correctly encoded (Base64 for binary) and perfectly recreated to support secure credential hashes.  
* Live Status Console embedded directly into the UI for real-time operation logging and transparency.  
* Right-click Context Menu added to the backup inventory list for rapid "Deploy/Restore" and "Delete" actions.  
* Localized backup directory creation (.\\ODBC Backups\\) dynamically scales relative to the execution path of the script using $PSScriptRoot.

### **Fixed**

* Replaced modern C\# 6.0 features (string interpolation and null-conditional operators) with C\# 5.0 compatible syntax (string.Format() and explicit null checks) to guarantee flawless compilation on native Windows PowerShell 5.1 environments.  
* Addressed PlaceholderText framework dependencies by mapping native Enter and Leave focus events for older .NET Framework targets.  
* Resolved threading errors when launching from Visual Studio Code / PowerShell ISE by exchanging Application.Run() with ShowDialog().  
* Stripped unsupported UI Emojis to prevent Mojibake rendering errors on legacy Windows terminal encodings.