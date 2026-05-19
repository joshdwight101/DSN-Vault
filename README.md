# **DSN-Vault 🔐**

**Universal ODBC Backup & Deployment Tool**

DSN-Vault is a portable, zero-dependency utility designed for Windows system administrators to seamlessly back up, organize, and deploy 32-bit and 64-bit ODBC Data Source Names (DSNs). By wrapping a high-performance C\# WinForms architecture inside a single PowerShell script, DSN-Vault enables precise, true-mirror deployments for database-heavy environments (like Sage 300, SAP Business One, SQL Server, and custom ERPs) without manual registry manipulation.

## **✨ Features**

* **AES-256 Payload Encryption**: Backups can be optionally secured with military-grade AES-256 encryption using PBKDF2 key derivation. Sensitive database credentials and network paths remain completely locked down at rest.  
* **True Mirroring**: Captures not just DSN strings, but underlying ODBCINST.INI driver registrations and complex payload types (Binary, DWord, MultiString) to ensure exact credential hashes and advanced settings are carried over.  
* **Selective Backups**: Dynamically scans the system and allows administrators to selectively check/uncheck specific System and User DSNs for surgical backups.  
* **Architecture Isolation**: Dedicated tabs for 32-bit and 64-bit ODBC trees, preventing accidental cross-contamination of legacy and modern drivers.  
* **Live Status Console**: An embedded, real-time terminal provides total transparency during deep registry extractions, encryption phases, and deployments.  
* **Contextual Management**: Right-click context menus allow for rapid deployment or deletion of XML payloads directly from the application UI.  
* **Zero Dependencies**: Entirely self-contained. The C\# UI, cryptography engine, and registry serializer are compiled entirely in memory on-the-fly by PowerShell.

## **🚀 Getting Started**

### **Prerequisites**

* Windows 10 or Windows 11\.  
* Windows PowerShell 5.1 (Built-in).  
* **Administrator Privileges** (Required to read/write HKLM registry hives).

### **Installation**

Because DSN-Vault is a standalone script, there is no installation required.

Simply download DSN-Vault.ps1 to your desired location (e.g., a secure network share or an IT utility USB drive).

### **Usage**

1. Right-click DSN-Vault.ps1 and select **Run with PowerShell**, or execute it directly from an elevated PowerShell terminal.  
2. The tool will automatically create an ODBC Backups directory in the same folder where the script resides.  
3. **To Backup**:  
   * Select your architecture tab (64-bit or 32-bit).  
   * Check the desired DSNs.  
   * Assign a friendly label (e.g., Finance\_Dept\_SQL).  
   * *(Optional)* Enter an encryption password to secure the payload.  
   * Click **Capture Backup**.  
4. **To Deploy**:  
   * Copy the script and the ODBC Backups folder to a new workstation and launch the script.  
   * *(Optional)* If the backup was encrypted, type the matching password into the password field.  
   * Right-click the desired backup in the list (or select it) and click **Deploy/Restore Backup**.

## **📂 Backup Schema**

Backups are serialized into highly portable XML payloads. If unencrypted, they use a standard \<ODBCBackup\> schema. If encrypted, they are wrapped in a \<SecureVault\> schema containing the cryptographic salt and ciphertext.

The naming convention automatically follows:

ODBC\_Backup\_yyyyMMdd\_HHmmss\_\[Architecture\]\_\[Label\].xml

## **⚠️ Important Note on Security**

DSN-Vault operates with elevated privileges to access protected machine-level registry keys (HKLM\\SOFTWARE\\ODBC and HKLM\\SOFTWARE\\WOW6432Node\\ODBC). While the XML backup payloads may contain sensitive network paths, database names, and obfuscated credentials, **utilizing the built-in AES-256 password feature** guarantees that this sensitive data cannot be extracted by unauthorized users who gain access to the raw XML files.