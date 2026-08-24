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
      --gray-600: #4b5563;
      --gray-700: #374151;
      --gray-800: #1f2937;
      --gray-900: #111827;
      --bg: var(--gray-50);
      --surface: #ffffff;
      --text: var(--gray-800);
      --heading: var(--gray-900);
      --on-accent: #ffffff;
      --nav-bg: var(--gray-900);
      --nav-text: #ffffff;
      --nav-muted: #d1d5db;
      --nav-hover: #374151;
      --input-bg: #ffffff;
      --choice-selected: #eef2ff;
      --shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
      color-scheme: light;
    }

    @media (prefers-color-scheme: dark) {
      :root {
        --primary: #818cf8;
        --primary-dark: #6366f1;
        --gray-50: #151b28;
        --gray-100: #1e2533;
        --gray-200: #2a3344;
        --gray-300: #3d4758;
        --gray-500: #9ca3af;
        --gray-600: #9ca3af;
        --gray-700: #d1d5db;
        --gray-800: #e5e7eb;
        --gray-900: #f3f4f6;
        --bg: #0b1220;
        --surface: #151b28;
        --text: #e5e7eb;
        --heading: #f9fafb;
        --nav-bg: #080c14;
        --nav-text: #f9fafb;
        --nav-muted: #9ca3af;
        --nav-hover: #1e2533;
        --input-bg: #0f1520;
        --choice-selected: #1e1b4b;
        --shadow: 0 1px 3px rgba(0, 0, 0, 0.45);
        color-scheme: dark;
      }

      .badge-new, .badge-public { background: #1e3a5f; color: #93c5fd; }
      .badge-processing, .badge-pending-images, .badge-test { background: #5b4510; color: #fde68a; }
      .badge-processed { background: #14532d; color: #86efac; }
      .badge-published { background: #312e81; color: #c7d2fe; }
      .badge-error { background: #7f1d1d; color: #fecaca; }
      .status-running { background: #14532d; color: #86efac; }
      .status-stopped { background: #7f1d1d; color: #fecaca; }
    }

    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }

    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: var(--bg);
      color: var(--text);
      line-height: 1.6;
    }

    /* Navbar */
    .navbar {
      background: var(--nav-bg);
      padding: 1rem 2rem;
      display: flex;
      align-items: center;
      justify-content: space-between;
    }

    .nav-brand a {
      color: var(--nav-text);
      font-size: 1.5rem;
      font-weight: bold;
      text-decoration: none;
      display: inline-flex;
      align-items: center;
      gap: 0.65rem;
    }

    .nav-logo {
      width: 2rem;
      height: 2rem;
      border-radius: 0.45rem;
      flex-shrink: 0;
    }

    .login-logo {
      display: block;
      width: 4rem;
      height: 4rem;
      margin: 0 auto 1rem;
      border-radius: 0.9rem;
    }

    .nav-links {
      display: flex;
      list-style: none;
      gap: 1.5rem;
    }

    .nav-links a {
      color: var(--nav-muted);
      text-decoration: none;
      padding: 0.5rem 1rem;
      border-radius: 6px;
      transition: all 0.2s;
    }

    .nav-links a:hover, .nav-links a.active {
      color: var(--nav-text);
      background: var(--nav-hover);
    }

    .nav-session {
      display: flex;
      align-items: center;
      gap: 0.75rem;
      margin-left: 0.5rem;
    }

    .nav-npub {
      color: var(--nav-muted);
      font-size: 0.75rem;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    }

    .nav-logout {
      display: inline;
      margin: 0;
    }

    .login-body {
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 2rem;
    }

    .login-card {
      background: var(--surface);
      padding: 2.5rem;
      border-radius: 12px;
      box-shadow: var(--shadow);
      max-width: 28rem;
      width: 100%;
    }

    .login-card h1 {
      margin-bottom: 0.5rem;
      text-align: center;
    }

    .login-lead {
      color: var(--gray-700);
      margin-bottom: 1.5rem;
      text-align: center;
    }

    .login-card .btn {
      width: 100%;
      margin: 1rem 0;
    }

    .btn[hidden],
    .login-error[hidden],
    [hidden] {
      display: none !important;
    }

    .login-error {
      color: var(--danger);
      font-size: 0.875rem;
      margin: 0.75rem 0;
    }

    /* Container */
    .container {
      max-width: 1200px;
      margin: 0 auto;
      padding: 2rem;
    }

    .container-wide {
      max-width: 92rem;
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
      color: var(--heading);
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
      background: var(--surface);
      padding: 1.5rem;
      border-radius: 12px;
      box-shadow: var(--shadow);
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
      background: var(--surface);
      border-radius: 8px;
      overflow: hidden;
      box-shadow: var(--shadow);
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

    .source-author {
      display: flex;
      align-items: center;
      gap: 0.75rem;
    }

    .source-avatar {
      width: 32px;
      height: 32px;
      border-radius: 50%;
      object-fit: cover;
      background: var(--gray-200);
      flex-shrink: 0;
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

    button.badge,
    a.badge {
      border: 0;
      font: inherit;
      font-size: 0.75rem;
      font-weight: 500;
      text-transform: uppercase;
      text-decoration: none;
      cursor: pointer;
      line-height: inherit;
    }

    button.badge:hover,
    a.badge:hover {
      filter: brightness(1.08);
    }

    .inline-mode-form {
      display: inline;
    }

    .badge-new { background: #dbeafe; color: #1d4ed8; }
    .badge-processing, .badge-pending-images { background: #fef3c7; color: #92400e; }
    .badge-processed { background: #d1fae5; color: #065f46; }
    .badge-published { background: #e0e7ff; color: #3730a3; }
    .badge-error { background: #fee2e2; color: #991b1b; }
    .badge-active { background: var(--success); color: var(--on-accent); }
    .badge-inactive { background: var(--gray-300); color: var(--gray-700); }
    .badge-test { background: #fef3c7; color: #92400e; }
    .badge-public { background: #dbeafe; color: #1d4ed8; }
    .badge-success { background: var(--success); color: var(--on-accent); }
    .badge-warning { background: var(--warning); color: var(--on-accent); }
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

    .btn:disabled,
    .btn[disabled] {
      opacity: 0.45;
      cursor: not-allowed;
      pointer-events: none;
      box-shadow: none;
    }

    .btn-primary {
      background: var(--primary);
      color: var(--on-accent);
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
      color: var(--on-accent);
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
      color: var(--on-accent);
    }

    /* Forms */
    .form {
      max-width: 500px;
      background: var(--surface);
      padding: 2rem;
      border-radius: 12px;
      box-shadow: var(--shadow);
    }

    .form-wide {
      max-width: 40rem;
    }

    .form-compose {
      max-width: none;
    }

    .compose-layout {
      display: grid;
      grid-template-columns: 1fr;
      gap: 1.5rem;
      margin-bottom: 1.5rem;
    }

    @media (min-width: 1100px) {
      .compose-layout {
        grid-template-columns: 26rem minmax(0, 1fr);
        align-items: start;
      }
    }

    .compose-fieldset {
      border: 1px solid var(--gray-200);
      border-radius: 8px;
      padding: 1rem;
      margin-bottom: 1.5rem;
    }

    .compose-fieldset legend {
      font-weight: 600;
      padding: 0 0.35rem;
      color: var(--heading);
    }

    .compose-advanced {
      border: 1px solid var(--gray-200);
      border-radius: 8px;
      padding: 0.75rem 1rem;
      margin-bottom: 1.5rem;
    }

    .compose-advanced summary {
      cursor: pointer;
      font-weight: 600;
      color: var(--heading);
    }

    .compose-advanced[open] summary {
      margin-bottom: 1rem;
    }

    .body-regions,
    .start-blocks {
      display: flex;
      flex-direction: column;
      gap: 0.5rem;
      margin-top: 0.75rem;
    }

    .body-region,
    .start-block {
      display: flex;
      flex-direction: column;
      align-items: flex-start;
      gap: 0.25rem;
      width: 100%;
      text-align: left;
      background: var(--surface);
      color: var(--text);
      border: 1px solid var(--gray-200);
      border-radius: 8px;
      padding: 0.75rem;
      cursor: pointer;
    }

    .body-region:hover,
    .start-block:hover {
      border-color: var(--primary);
    }

    .body-region.is-selected,
    .start-block.is-selected {
      border-color: var(--primary);
      background: var(--choice-selected);
    }

    .body-region-badge {
      display: inline-block;
      margin-left: 0.5rem;
      padding: 0.1rem 0.4rem;
      border-radius: 999px;
      background: var(--primary);
      color: var(--on-accent);
      font-size: 0.6875rem;
      font-weight: 600;
      vertical-align: middle;
    }

    .compose-preview-panel {
      background: var(--input-bg);
      border: 1px solid var(--gray-200);
      border-radius: 8px;
      padding: 1rem;
      position: sticky;
      top: 1rem;
    }

    .compose-preview-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 0.75rem;
      margin-bottom: 0.75rem;
    }

    .compose-preview-header label {
      margin: 0;
      font-weight: 600;
    }

    .compose-original-article {
      margin: 0.35rem 0 0;
      font-size: 0.875rem;
    }

    .compose-preview-actions {
      display: flex;
      align-items: center;
      flex-wrap: wrap;
      gap: 0.75rem;
    }

    .compose-split-toggle {
      display: flex;
      align-items: center;
      gap: 0.4rem;
      margin: 0;
      font-size: 0.8125rem;
      font-weight: 500;
      color: var(--gray-600);
      white-space: nowrap;
      cursor: pointer;
    }

    .compose-split-toggle[hidden] {
      display: none;
    }

    .compose-split-toggle input {
      width: auto;
      margin: 0;
    }

    .compose-preview-part {
      white-space: normal;
    }

    .compose-preview-part + .compose-preview-part {
      margin-top: 1.75rem;
      padding-top: 1.5rem;
      border-top: 2px dashed var(--gray-300);
    }

    .compose-preview-part-label {
      margin: 0 0 0.75rem;
      font-size: 0.75rem;
      font-weight: 600;
      letter-spacing: 0.04em;
      text-transform: uppercase;
      color: var(--gray-600);
    }

    .compose-preview-part-markdown {
      margin: 0;
      white-space: pre-wrap;
      word-break: break-word;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      font-size: 0.8125rem;
      line-height: 1.5;
    }

    .source-tabs {
      display: flex;
      gap: 0.25rem;
      margin-bottom: 1.5rem;
      border-bottom: 1px solid var(--gray-200);
    }

    .source-tab {
      padding: 0.6rem 1rem;
      color: var(--gray-600);
      text-decoration: none;
      border-bottom: 2px solid transparent;
      margin-bottom: -1px;
    }

    .source-tab.is-active {
      color: var(--heading);
      border-bottom-color: var(--primary);
      font-weight: 600;
    }

    .compose-tabs {
      display: flex;
      border: 1px solid var(--gray-200);
      border-radius: 6px;
      overflow: hidden;
    }

    .compose-tab {
      background: var(--surface);
      color: var(--gray-600);
      border: 0;
      padding: 0.4rem 0.75rem;
      font-size: 0.8125rem;
      cursor: pointer;
    }

    .compose-tab + .compose-tab {
      border-left: 1px solid var(--gray-200);
    }

    .compose-tab.is-active {
      background: var(--primary);
      color: var(--on-accent);
    }

    .compose-preview-meta {
      color: var(--gray-600);
      font-size: 0.8125rem;
      line-height: 1.5;
      margin-bottom: 0.75rem;
      padding-bottom: 0.75rem;
      border-bottom: 1px solid var(--gray-200);
    }

    .compose-preview,
    .compose-preview-rendered {
      max-height: calc(100vh - 12rem);
      overflow: auto;
      color: var(--text);
    }

    .compose-preview {
      white-space: pre-wrap;
      word-break: break-word;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      font-size: 0.8125rem;
      line-height: 1.5;
      margin: 0;
    }

    .compose-preview-rendered {
      font-size: 1.05rem;
      line-height: 1.7;
    }

    .compose-preview-rendered h1,
    .compose-preview-rendered h2,
    .compose-preview-rendered h3,
    .compose-preview-rendered h4 {
      color: var(--heading);
      line-height: 1.3;
      margin: 1.25rem 0 0.6rem;
    }

    .compose-preview-rendered h1 {
      font-size: 1.75rem;
      margin-top: 0;
    }

    .compose-preview-rendered p,
    .compose-preview-rendered ul,
    .compose-preview-rendered ol,
    .compose-preview-rendered blockquote,
    .compose-preview-rendered pre {
      margin: 0 0 1rem;
    }

    .compose-preview-rendered img {
      max-width: 100%;
      height: auto;
      border-radius: 8px;
    }

    .compose-preview-rendered a img[src*="fontawesome"] {
      height: 1.15em;
      width: auto;
      display: inline;
      vertical-align: -0.15em;
      margin-right: 0.3em;
      border-radius: 0;
    }

    .compose-preview-rendered figure {
      margin: 0 0 1.25rem;
    }

    .compose-preview-rendered figcaption {
      margin-top: 0.4rem;
      font-size: 0.9em;
      color: var(--gray-600);
      text-align: center;
    }

    .compose-preview-rendered a {
      color: var(--primary);
    }

    .compose-preview-rendered .footnote-ref {
      font-size: 0.75em;
      line-height: 0;
    }

    .compose-preview-rendered .footnote {
      font-size: 0.92em;
    }

    .compose-preview-rendered blockquote {
      border-left: 3px solid var(--gray-300);
      padding-left: 1rem;
      color: var(--gray-600);
    }

    .compose-preview-rendered pre,
    .compose-preview-rendered code {
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      font-size: 0.9em;
    }

    .compose-hero {
      margin: 0 0 0.75rem;
      padding-bottom: 0.75rem;
      border-bottom: 1px solid var(--gray-200);
      text-align: center;
    }

    .compose-hero[hidden] {
      display: none;
    }

    .compose-hero img {
      display: block;
      margin: 0 auto;
      max-width: 100%;
      max-height: 20rem;
      width: auto;
      height: auto;
      object-fit: contain;
    }

    .form-group textarea:focus {
      outline: none;
      border-color: var(--primary);
      box-shadow: 0 0 0 3px rgba(99, 102, 241, 0.1);
    }

    .input-row {
      display: flex;
      gap: 0.75rem;
    }

    .input-row input {
      flex: 1;
    }

    .choice-list {
      display: flex;
      flex-direction: column;
      gap: 0.5rem;
    }

    .choice {
      display: flex;
      gap: 0.75rem;
      align-items: flex-start;
      padding: 0.75rem;
      border: 1px solid var(--gray-200);
      border-radius: 8px;
      cursor: pointer;
    }

    .choice:has(input:checked) {
      border-color: var(--primary);
      background: var(--choice-selected);
    }

    .choice input {
      width: auto;
      margin-top: 0.25rem;
    }

    .choice span {
      display: flex;
      flex-direction: column;
      gap: 0.25rem;
      min-width: 0;
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
      background: var(--input-bg);
      color: var(--text);
    }

    .post-editor-markdown {
      min-height: 28rem;
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      font-size: 0.95rem;
      line-height: 1.5;
    }

    .form-group input:focus, .form-group select:focus {
      outline: none;
      border-color: var(--primary);
      box-shadow: 0 0 0 3px rgba(99, 102, 241, 0.1);
    }

    .form-group.checkbox label {
      display: flex;
      align-items: center;
      gap: 0.5rem;
      font-weight: 500;
    }

    .form-group input[type="checkbox"] {
      width: auto;
      margin: 0;
    }

    .form-actions {
      display: flex;
      gap: 1rem;
      margin-top: 2rem;
    }

    .article-toolbar {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 0.75rem;
      margin: 0 0 1rem;
    }

    .article-toolbar form {
      display: inline;
      margin: 0;
    }

    .article-select {
      width: 2rem;
      text-align: center;
      vertical-align: middle;
    }

    .article-select input {
      width: auto;
      margin: 0;
    }

    .error {
      color: var(--danger);
      font-size: 0.875rem;
      margin-top: 0.25rem;
    }

    /* Dashboard Sections */
    .dashboard-section {
      background: var(--surface);
      padding: 1.5rem;
      border-radius: 12px;
      box-shadow: var(--shadow);
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
      flex-wrap: wrap;
      gap: 0.5rem;
      align-items: center;
      margin-bottom: 1.5rem;
    }

    .filter-source {
      margin-left: auto;
      display: flex;
      gap: 0.5rem;
      align-items: center;
    }

    .filter-source label {
      font-size: 0.875rem;
      color: var(--gray-600);
    }

    .filter-source select,
    .filter-source input[type="search"] {
      min-width: 12rem;
      padding: 0.35rem 0.5rem;
    }

    .filter-source input[type="search"] {
      min-width: 14rem;
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
      background: var(--surface);
      padding: 1.5rem;
      border-radius: 12px;
      box-shadow: var(--shadow);
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
      background: var(--surface);
      padding: 1.5rem;
      border-radius: 12px;
      box-shadow: var(--shadow);
      margin-bottom: 1.5rem;
    }

    .scheduler-section {
      background: var(--surface);
      padding: 1.5rem;
      border-radius: 12px;
      box-shadow: var(--shadow);
      margin-bottom: 1.5rem;
    }

    .scheduler-section h2 {
      margin-top: 0;
    }

    /* Post Detail */
    .post-meta {
      background: var(--surface);
      padding: 1.5rem;
      border-radius: 12px;
      box-shadow: var(--shadow);
      margin-bottom: 1.5rem;
    }

    .post-meta p {
      margin: 0.5rem 0;
    }

    .post-actions {
      margin-bottom: 1.5rem;
    }

    .post-image {
      background: var(--surface);
      padding: 1.5rem;
      border-radius: 12px;
      box-shadow: var(--shadow);
      margin-bottom: 1.5rem;
    }

    .post-image img {
      border-radius: 8px;
    }

    .post-content {
      background: var(--surface);
      padding: 1.5rem;
      border-radius: 12px;
      box-shadow: var(--shadow);
      margin-bottom: 1.5rem;
    }

    .content-preview {
      max-height: 400px;
      overflow-y: auto;
    }

    .post-source {
      background: var(--surface);
      padding: 1.5rem;
      border-radius: 12px;
      box-shadow: var(--shadow);
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
