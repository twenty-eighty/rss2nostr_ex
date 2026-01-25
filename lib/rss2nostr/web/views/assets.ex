defmodule Rss2Nostr.Web.Views.Assets do
  @moduledoc """
  Static assets (CSS) for the web interface.
  """

  def css do
    """
    :root {
      --primary: #6366f1;
      --primary-dark: #4f46e5;
      --success: #22c55e;
      --warning: #f59e0b;
      --danger: #ef4444;
      --gray-50: #f9fafb;
      --gray-100: #f3f4f6;
      --gray-200: #e5e7eb;
      --gray-300: #d1d5db;
      --gray-500: #6b7280;
      --gray-700: #374151;
      --gray-800: #1f2937;
      --gray-900: #111827;
    }

    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }

    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: var(--gray-50);
      color: var(--gray-800);
      line-height: 1.6;
    }

    /* Navbar */
    .navbar {
      background: var(--gray-900);
      padding: 1rem 2rem;
      display: flex;
      align-items: center;
      justify-content: space-between;
    }

    .nav-brand a {
      color: white;
      font-size: 1.5rem;
      font-weight: bold;
      text-decoration: none;
    }

    .nav-links {
      display: flex;
      list-style: none;
      gap: 1.5rem;
    }

    .nav-links a {
      color: var(--gray-300);
      text-decoration: none;
      padding: 0.5rem 1rem;
      border-radius: 6px;
      transition: all 0.2s;
    }

    .nav-links a:hover, .nav-links a.active {
      color: white;
      background: var(--gray-700);
    }

    /* Container */
    .container {
      max-width: 1200px;
      margin: 0 auto;
      padding: 2rem;
    }

    /* Footer */
    .footer {
      text-align: center;
      padding: 2rem;
      color: var(--gray-500);
      font-size: 0.875rem;
    }

    /* Typography */
    h1 {
      font-size: 2rem;
      margin-bottom: 1.5rem;
      color: var(--gray-900);
    }

    h2 {
      font-size: 1.5rem;
      margin: 1.5rem 0 1rem;
      color: var(--gray-800);
    }

    h3 {
      font-size: 1.25rem;
      margin: 1rem 0 0.5rem;
    }

    a {
      color: var(--primary);
    }

    code {
      background: var(--gray-100);
      padding: 0.125rem 0.375rem;
      border-radius: 4px;
      font-size: 0.875rem;
    }

    pre {
      background: var(--gray-100);
      padding: 1rem;
      border-radius: 8px;
      overflow-x: auto;
      font-size: 0.875rem;
      white-space: pre-wrap;
      word-wrap: break-word;
    }

    /* Page Header */
    .page-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 1.5rem;
    }

    .page-header h1 {
      margin-bottom: 0;
    }

    /* Stats Grid */
    .stats-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
      gap: 1.5rem;
      margin-bottom: 2rem;
    }

    .stat-card {
      background: white;
      padding: 1.5rem;
      border-radius: 12px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.1);
      text-align: center;
    }

    .stat-value {
      font-size: 2.5rem;
      font-weight: bold;
      color: var(--primary);
    }

    .stat-label {
      font-size: 1rem;
      color: var(--gray-700);
      margin-top: 0.5rem;
    }

    .stat-detail {
      font-size: 0.875rem;
      color: var(--gray-500);
    }

    /* Tables */
    .table {
      width: 100%;
      border-collapse: collapse;
      background: white;
      border-radius: 8px;
      overflow: hidden;
      box-shadow: 0 1px 3px rgba(0,0,0,0.1);
    }

    .table th, .table td {
      padding: 1rem;
      text-align: left;
      border-bottom: 1px solid var(--gray-200);
    }

    .table th {
      background: var(--gray-50);
      font-weight: 600;
      color: var(--gray-700);
    }

    .table tr:hover {
      background: var(--gray-50);
    }

    .table .actions {
      white-space: nowrap;
    }

    /* Badges */
    .badge {
      display: inline-block;
      padding: 0.25rem 0.75rem;
      border-radius: 9999px;
      font-size: 0.75rem;
      font-weight: 500;
      text-transform: uppercase;
    }

    .badge-new { background: #dbeafe; color: #1d4ed8; }
    .badge-processing { background: #fef3c7; color: #92400e; }
    .badge-processed { background: #d1fae5; color: #065f46; }
    .badge-published { background: #e0e7ff; color: #3730a3; }
    .badge-error { background: #fee2e2; color: #991b1b; }
    .badge-active { background: var(--success); color: white; }
    .badge-inactive { background: var(--gray-300); color: var(--gray-700); }
    .badge-success { background: var(--success); color: white; }
    .badge-warning { background: var(--warning); color: white; }
    .badge-idle { background: var(--gray-200); color: var(--gray-600); }

    /* Buttons */
    .btn {
      display: inline-block;
      padding: 0.625rem 1.25rem;
      border-radius: 6px;
      font-size: 0.875rem;
      font-weight: 500;
      text-decoration: none;
      border: none;
      cursor: pointer;
      transition: all 0.2s;
    }

    .btn-primary {
      background: var(--primary);
      color: white;
    }

    .btn-primary:hover {
      background: var(--primary-dark);
    }

    .btn-secondary {
      background: var(--gray-200);
      color: var(--gray-700);
    }

    .btn-secondary:hover {
      background: var(--gray-300);
    }

    .btn-danger {
      background: var(--danger);
      color: white;
    }

    .btn-danger:hover {
      background: #dc2626;
    }

    .btn-small {
      padding: 0.375rem 0.75rem;
      font-size: 0.75rem;
    }

    .btn-active {
      background: var(--primary);
      color: white;
    }

    /* Forms */
    .form {
      max-width: 500px;
      background: white;
      padding: 2rem;
      border-radius: 12px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.1);
    }

    .form-group {
      margin-bottom: 1.5rem;
    }

    .form-group label {
      display: block;
      margin-bottom: 0.5rem;
      font-weight: 500;
      color: var(--gray-700);
    }

    .form-group input, .form-group select, .form-group textarea {
      width: 100%;
      padding: 0.75rem;
      border: 1px solid var(--gray-300);
      border-radius: 6px;
      font-size: 1rem;
    }

    .form-group input:focus, .form-group select:focus {
      outline: none;
      border-color: var(--primary);
      box-shadow: 0 0 0 3px rgba(99, 102, 241, 0.1);
    }

    .form-actions {
      display: flex;
      gap: 1rem;
      margin-top: 2rem;
    }

    .error {
      color: var(--danger);
      font-size: 0.875rem;
      margin-top: 0.25rem;
    }

    /* Dashboard Sections */
    .dashboard-section {
      background: white;
      padding: 1.5rem;
      border-radius: 12px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.1);
      margin-bottom: 1.5rem;
    }

    .dashboard-section h2 {
      margin-top: 0;
    }

    /* Status Indicator */
    .status-indicator {
      display: inline-block;
      padding: 0.5rem 1rem;
      border-radius: 6px;
      font-weight: 500;
    }

    .status-running {
      background: #d1fae5;
      color: #065f46;
    }

    .status-stopped {
      background: #fee2e2;
      color: #991b1b;
    }

    /* Action Buttons */
    .action-buttons {
      display: flex;
      gap: 0.75rem;
      flex-wrap: wrap;
    }

    /* Filter Bar */
    .filter-bar {
      display: flex;
      gap: 0.5rem;
      margin-bottom: 1.5rem;
    }

    /* Pagination */
    .pagination {
      display: flex;
      justify-content: center;
      align-items: center;
      gap: 1rem;
      margin-top: 1.5rem;
    }

    /* Empty State */
    .empty-state {
      text-align: center;
      padding: 2rem;
      color: var(--gray-500);
    }

    /* Settings */
    .settings-section {
      background: white;
      padding: 1.5rem;
      border-radius: 12px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.1);
      margin-bottom: 1.5rem;
    }

    .settings-section h2 {
      margin-top: 0;
    }

    .setting-item {
      padding: 1rem 0;
      border-bottom: 1px solid var(--gray-200);
    }

    .setting-item:last-child {
      border-bottom: none;
    }

    .setting-item label {
      display: block;
      font-weight: 500;
      margin-bottom: 0.5rem;
    }

    .help-text {
      font-size: 0.875rem;
      color: var(--gray-500);
      margin-top: 0.5rem;
    }

    /* Scheduler */
    .scheduler-status {
      display: flex;
      justify-content: space-between;
      align-items: center;
      background: white;
      padding: 1.5rem;
      border-radius: 12px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.1);
      margin-bottom: 1.5rem;
    }

    .scheduler-section {
      background: white;
      padding: 1.5rem;
      border-radius: 12px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.1);
      margin-bottom: 1.5rem;
    }

    .scheduler-section h2 {
      margin-top: 0;
    }

    /* Post Detail */
    .post-meta {
      background: white;
      padding: 1.5rem;
      border-radius: 12px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.1);
      margin-bottom: 1.5rem;
    }

    .post-meta p {
      margin: 0.5rem 0;
    }

    .post-actions {
      margin-bottom: 1.5rem;
    }

    .post-image {
      background: white;
      padding: 1.5rem;
      border-radius: 12px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.1);
      margin-bottom: 1.5rem;
    }

    .post-image img {
      border-radius: 8px;
    }

    .post-content {
      background: white;
      padding: 1.5rem;
      border-radius: 12px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.1);
      margin-bottom: 1.5rem;
    }

    .content-preview {
      max-height: 400px;
      overflow-y: auto;
    }

    .post-source {
      background: white;
      padding: 1.5rem;
      border-radius: 12px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.1);
    }

    .post-source summary {
      cursor: pointer;
      font-weight: 500;
    }

    /* Error Page */
    .error-page {
      text-align: center;
      padding: 4rem 2rem;
    }

    .error-page h1 {
      color: var(--danger);
    }

    /* URL display */
    .url {
      font-size: 0.8rem;
      word-break: break-all;
    }

    /* Success/Warning text */
    .success { color: var(--success); }
    .warning { color: var(--warning); }
    """
  end
end
