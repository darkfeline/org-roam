(require 'deft)
(require 'dash)
(require 'ht)

(defgroup org-roam nil
  "Roam Research replica in Org-mode."
  :group 'org
  :prefix "org-roam-")

(defcustom org-roam-zettel-indicator "§"
  "Indicator in front of a zettel.")

(defvar org-roam-buffer "*org-roam*"
  "Org-roam buffer name.")

(defcustom org-roam-position 'right
  "Position of `org-roam' buffer.

Valid values are
 * left,
 * right."
  :type '(choice (const left)
                 (const right))
  :group 'org-roam)

(defvar org-roam-hash-backlinks nil
  "Cache containing backlinks for `org-roam' buffers.")

(defvar org-roam-current-file nil
  "The current file being shown in the `org-roam' buffer.")

(define-inline org-roam-current-visibility ()
  "Return whether the current visibility state of the org-roam buffer.
Valid states are 'visible, 'exists and 'none."
  (declare (side-effect-free t))
  (inline-quote
   (cond
    ((get-buffer-window org-roam-buffer) 'visible)
    ((get-buffer org-roam-buffer) 'exists)
    (t 'none))))

(defun org-roam-insert (file-name)
  "Find file `FILE-NAME', insert it as a link with the base file name as the link name."
  (interactive (list (completing-read "File: " (deft-find-all-files-no-prefix))))
  (let ((org-link-file-type 'relative))
    (org-insert-link nil (concat "file:" (concat deft-directory file-name))
                     (concat org-roam-zettel-indicator (file-name-base file-name)))))

(defun org-roam-get-linked-files ()
  "Show links to this file."
  (interactive)
  (let* ((search-term (file-name-nondirectory buffer-file-name))
         (files deft-all-files)
	       (tnames (mapcar #'file-truename files)))
    (multi-occur
     (mapcar (lambda (x)
	             (with-current-buffer
		               (or (get-file-buffer x) (find-file-noselect x))
		             (widen)
		             (current-buffer)))
	           files)
     search-term
     3)))

(defun org-roam-get-links-from-buffer (buffer)
  "Return a list of links from an Org BUFFER."
  (with-current-buffer buffer
    (org-element-map (org-element-parse-buffer) 'link
      (lambda (link)
        (let ((type (org-element-property :type link))
              (path (org-element-property :path link)))
          (when (and (string= type "file")
                     (string= (file-name-extension path) "org"))
            path))))))


(defun org-roam-build-backlinks ()
  "Builds the backlink hash table, saving it into `org-roam-hash-backlinks'."
  (message "building backlinks...")
  (let ((backlinks (ht)))
    (-map (lambda (file)
            (with-temp-buffer
              (insert-file-contents file)
              (-map (lambda (link)
                      (let* ((item (ht-get backlinks link))
                             (added-item (file-name-nondirectory file))
                             (updated (if (and item)
                                          (if (member added-item item)
                                              item
                                            (cons added-item item))
                                        (list added-item))))
                        (ht-set! backlinks link updated)))
                    (org-roam-get-links-from-buffer (current-buffer)))))
          (deft-find-all-files))
    (setq org-roam-hash-backlinks backlinks)))

(defun org-roam-new-file-named (slug)
  "Create a new file named `SLUG'.
`SLUG' is the short file name, without a path or a file extension."
  (interactive "sNew filename (without extension): ")
  (let ((file (deft-absolute-filename slug)))
    (unless (file-exists-p file)
      (deft-auto-populate-title-maybe file)
      (deft-cache-update-file file)
      (deft-refresh-filter))
    (deft-open-file file)))

(defun org-roam-today ()
  "Creates the file for today."
  (interactive)
  (org-roam-new-file-named (format-time-string "%Y-%m-%d" (current-time))))

(defun org-roam-update (file)
  (interactive)
  "Show the backlinks for the current org-buffer."
  (unless (string= org-roam-current-file file)
    (unless org-roam-hash-backlinks
      (org-roam-build-backlinks))
    (let ((backlinks (ht-get org-roam-hash-backlinks file)))
      (with-current-buffer org-roam-buffer
        (read-only-mode -1)
        (erase-buffer)
        (org-mode)
        (make-local-variable 'org-return-follows-link)
        (setq org-return-follows-link t)
        (insert (format "Backlinks for %s:\n\n" file))
        (-map (lambda (link)
                (insert (format "- [[file:%s][%s]]\n" (expand-file-name link deft-directory) link))
                ) backlinks)
        (read-only-mode +1))))
  (setq org-roam-current-file file))

(defun org-roam ()
  "Initialize org-roam."
  (interactive)
  (add-hook 'post-command-hook 'org-roam-update-buffer)
  (pcase (org-roam-current-visibility)
    ('visible (delete-window (get-buffer-window org-roam-buffer)))
    ('exists (org-roam-setup-buffer))
    ('none (org-roam-setup-buffer))))

(defun org-roam-setup-buffer ()
  "Sets up the org-roam buffer at the side."
  (-> (get-buffer-create org-roam-buffer)
      (display-buffer-in-side-window `((side . ,org-roam-position)))))

(defun org-roam-update-buffer ()
  (interactive)
  (when (and (eq major-mode 'org-mode)
             (not (string= org-roam-current-file (buffer-file-name (current-buffer))))
             (member (buffer-file-name (current-buffer)) (deft-find-all-files)))
    (org-roam-update (file-name-nondirectory (buffer-file-name (current-buffer))))))

(provide 'org-roam)
