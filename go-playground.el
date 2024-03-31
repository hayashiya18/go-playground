;;; go-playground.el --- Local Golang playground for short snippets.

;; Copyright (C) 2015-2024 Alexander I.Grafov and the project
;; contibutors.

;; Author: Alexander I.Grafov <grafov@inet.name>
;; URL: https://github.com/grafov/go-playground
;; Keywords: tools, golang
;; Version: 1.8.2
;; Package-Requires: ((emacs "24") (gotest "0.13.0"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Local playground for the Go programs similar to play.golang.org.
;; `M-x go-playground` and type you golang code then make&run it with `C-Return`.

;; Playground works around `go-mode` and requires preconfigured environment
;; for Go language.

;; I recommend you to use `goimports` instead of `gofmt` for automatically make
;; import clauses. It very comfortable especially for experimenting with code
;; in playground.

;; You may push code to play.golang.org with go-mode' function `go-play-buffer`.

;;

;;; Code:

;; go-mode or go-ts-mode is required for this package.
(unless (or (require 'go-ts-mode nil t) (require 'go-mode nil t))
    (error "go-mode or go-ts-mode is required for go-playground"))
;; go-command is declared in go-mode but not in go-ts-mode.
(unless (boundp 'go-command)
  (setq go-command "go"))

(require 'gotest)
(require 'compile)
(require 'time-stamp)
(require 'subr-x)

(defgroup go-playground nil
  "Options specific to Go Playground."
  :group 'go)

(defcustom go-playground-ask-file-name nil
  "Non-nil means we ask for a name for the snippet.

By default it will be created as snippet.go"
  :type 'boolean
  :group 'go-playground)

(defcustom go-playground-confirm-deletion t
  "Non-nil means you will be asked for confirmation on the snippet deletion with `go-playground-rm'.

By default confirmation required."
  :type 'boolean
  :group 'go-playground)

(defcustom go-playground-basedir "~/go/src/playground"
  "Base directory for playground snippets.  Better to set it under GOPATH."
  :type 'file
  :group 'go-playground)

(defcustom go-playground-compile-command (concat go-command " mod tidy; " go-command " run ./...")
  "The commands used for compilation.

Use \";\" or any other appropriate shell separator if you need several commands in one session."
  :type 'string
  :group 'go-playground)

(defcustom go-playground-pre-rm-hook nil
  "Hook run before a snippet is removed."
  :type 'hook
  :group 'go-playground)

(defcustom go-playground-init-command "go mod init"
  "The shell command executed once when the snippet just created."
  :type 'string
  :group 'go-playground)

;;;###autoload
(define-minor-mode go-playground-mode
  "A place for playing with golang code and export it in short snippets."
  :init-value nil
  :lighter "Play(Go)"
  :keymap '(([C-return] . go-playground-exec)
	    ([M-return] . go-playground-cmd)))

(defun go-playground-snippet-file-name(&optional snippet-name)
  (let* ((file-name (cond (snippet-name)
			 (go-playground-ask-file-name
			  (read-string "Go Playground filename: "))
			 ("snippet")))
	 (snippet-dir (go-playground-snippet-unique-dir file-name)))
    (let ((default-directory snippet-dir))
      (call-process-shell-command go-playground-init-command))
    (concat snippet-dir "/" file-name ".go")))

;
(defun go-playground-save-and-run ()
  "Obsoleted by go-playground-exec."
  (interactive)

  (go-playground-exec))

(defun go-playground-exec ()
  "Save the buffer then runs Go compiler for executing the code."
  (interactive)
  (if (go-playground-inside)
	  (progn
		(save-buffer t)
		(make-local-variable 'compile-command)
		(compile go-playground-compile-command))))

(defun go-playground-cmd (cmd)
  "Save the buffer then apply custom compile command from
minibuffer to the files or buffer."
  (interactive "scompile command: ")
  (if (go-playground-inside)
	  (progn
		(save-buffer t)
		(make-local-variable 'compile-command)
		(compile cmd))))

;;;###autoload
(defun go-playground ()
  "Run playground for Go language in a new buffer."
  (interactive)
  (let ((snippet-file-name (go-playground-snippet-file-name)))
	(switch-to-buffer (create-file-buffer snippet-file-name))
	(go-playground-insert-template-head "snippet of code")
(insert "package main

import (
	\"fmt\"
)

func main() {
	fmt.Println(\"Results:\")
}
")
	(backward-char 3)
    (go-playground--turn-on-go-major-mode)
	(go-playground-mode)
	(set-visited-file-name snippet-file-name t)))

(defun go-playground-insert-template-head (description)
  (insert "// -*- mode:" (if (eq (go-playground--use-major-mode-eval) 'go-mode) "go" "go-ts") ";mode:go-playground -*-
// " description " @ " (time-stamp-string "%:y-%02m-%02d %02H:%02M:%02S") "

// === Go Playground ===
// Execute the snippet with:                 Ctl-Return
// Provide custom arguments to compile with: Alt-Return
// Other useful commands:
// - remove the snippet completely with its dir and all files: (go-playground-rm)
// - upload the current buffer to playground.golang.org:       (go-playground-upload)

"))

(defun go-playground-rm ()
  "Remove files of the current snippet together with directory of this snippet."
  (interactive)
  (if (go-playground-inside)
	  (if (or (not go-playground-confirm-deletion)
			  (y-or-n-p (format "Do you want delete whole snippet dir %s? "
								(file-name-directory (buffer-file-name)))))
		  (progn
			(save-buffer)
			(run-hooks 'go-playground-pre-rm-hook)
			(delete-directory (file-name-directory (buffer-file-name)) t t)
			(kill-buffer)))
	(message "Won't delete this! Because %s is not under the path %s. Remove the snippet manually!"
			 (buffer-file-name) go-playground-basedir)))

;;;###autoload
(defun go-playground-remove-current-snippet ()
	"Obsoleted by `go-playground-rm'."
  (interactive)
  (go-playground-rm))

;;;###autoload
(defun go-playground-download (url)
  "Download a paste from the play.golang.org and insert it in a new local playground buffer.
Tries to look for a URL at point."
  (interactive (list (read-from-minibuffer "Playground URL: " (ffap-url-p (ffap-string-at-point 'url)))))
  (with-current-buffer
	  (let ((url-request-method "GET") url-request-data url-request-extra-headers)
		(url-retrieve-synchronously (concat url ".go")))
	(let* ((snippet-file-name (go-playground-snippet-file-name)) (buffer (create-file-buffer snippet-file-name)))
	  (goto-char (point-min))
	  (re-search-forward "\n\n")
	  (copy-to-buffer buffer (point) (point-max))
	  (kill-buffer)
	  (with-current-buffer buffer
		(goto-char (point-min))
		(go-playground-insert-template-head (concat url " imported"))
        (go-playground--turn-on-go-major-mode)
		(go-playground-mode)
		(set-visited-file-name snippet-file-name t)
		(switch-to-buffer buffer)))))

(defun go-playground-upload ()
  "Upload the current buffer to play.golang.org and return the short URL of the playground."
  (interactive)
  (if (not (go-playground-inside))
      (message "Not in a Go Playground buffer!")
    (go-play-buffer)))

(defun go-playground-snippet-unique-dir (prefix)
  "Get unique directory under GOPATH/`go-playground-basedir`."
  (let ((dir-name (concat go-playground-basedir "/"
						  (if (and prefix go-playground-ask-file-name) (concat prefix "-"))
						  (time-stamp-string "at-%:y-%02m-%02d-%02H%02M%02S"))))
	(make-directory dir-name t)
	dir-name))

(defun go-playground-inside ()
  "Is the current buffer is valid go-playground buffer."
  (and (bound-and-true-p go-playground-mode)
       buffer-file-name
       (string-prefix-p (file-truename go-playground-basedir)
			(file-truename buffer-file-name))))

(defcustom go-playground-use-major-mode 'auto
  "Major mode to use for Go Playground.

If set to 'auto, go-ts-mode will be used if available.
If set to 'go-ts-mode, go-ts-mode will be used.
If set to 'go-mode, go-mode will be used.
"
  :type '(choice (const :tag "Auto" auto)
                 (const :tag "go-ts-mode" go-ts-mode)
                 (const :tag "go-mode" go-mode))
  :group 'go-playground)

(defun go-playground--use-major-mode-eval ()
  "Evaluate `go-playground-use-major-mode'."
  (cond ((eq go-playground-use-major-mode 'auto)
         (if (require 'go-ts-mode nil t)
             'go-ts-mode
           'go-mode))
        ((eq go-playground-use-major-mode 'go-ts-mode)
         'go-ts-mode)
        ((eq go-playground-use-major-mode 'go-mode)
         'go-mode)
        (t
         (error "Invalid value for `go-playground-use-major-mode'"))))

(defun go-playground--turn-on-go-major-mode ()
  "Turn on the major mode specified by `go-playground-use-major-mode'."
  (let ((v (go-playground--use-major-mode-eval)))
    (cond ((eq v 'go-ts-mode)
           (go-ts-mode))
          ((eq v 'go-mode)
           (go-mode))
          (t
           (error "Invalid value for `go-playground-use-major-mode'")))))

(provide 'go-playground)
;;; go-playground.el ends here
