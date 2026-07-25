/**
 * Sunday Publishing Platform — TipTap Draggable Extension
 * 
 * Copyright (c) 2026 George Lemon. All rights reserved.
 * 
 * Sunday is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License (AGPLv3)
 * as published by the Free Software Foundation.
 *
 * For more information, documentation, and contributing:
 * 👉 https://github.com/openpeeps/sunday
 */

import SundayEditor from './modules/SundayEditor.js'
import MultiModalManager from './modules/MultiModalManager.js'
import GroupedDragDrop from './modules/StupidDragDrop.js'
export {MultiModalManager, GroupedDragDrop}

export const Editor = {
  init: (data, postId) => {
    let editorSelector = document.querySelector('.editor-wrapper')
    let inputTitleElement = document.querySelector('#form-action-title')
    let currentPath = window.location.pathname;
    if(!editorSelector || !inputTitleElement) return;
    let Editor = new SundayEditor({
      target: editorSelector,
      inputTitleElement: inputTitleElement,
      saveButtonCallback: (editor, toolbar, inputTitle) => {
        let saveButton = document.querySelector('#btn-action-save');
        saveButton.addEventListener('click', (e) => {
          e.preventDefault();
          e.stopPropagation();
          
          // disable the editor while saving the content
          toolbar.style.display = 'none';
          editor.setEditable(false);

          function resetEditorState() {
            saveButton.classList.remove('d-none');
            toolbar.style.display = '';
            editor.setEditable(true);
          }

          console.log(editor.getJSON())
          fetch('/dashboard/posts/create', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({
              id: postId ? (parseInt(postId) || null) : null,
              title: inputTitle.value,
              content: editor.getJSON()
            })
          }).then(async (res) => {
            let data = await res.json();
            window.location.href = `/dashboard/posts/${data.post_id}`;
          });
        });
      },
      css: {
        textEditorWidth: '100%',
        textEditorMargin: 'auto',
      },
    })

    // load the editor with existing data
    if(data) {
      Editor.editorInstance.commands.setContent(data, {
        parseOptions: { errorOnInvalidContent: true }
      });
      
      // Editor.editorInstance.commands.setImage({
      //   src: 'https://images.unsplash.com/photo-1760710120674-1a2583b3bf9e?ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&q=80&w=1170',
      //   alt: 'A boring example image',
      //   title: 'An example',
      // })
    }
  }
}

export const ClientSideForms = {
  init: (opts = {}) => {
    function resetSubmitter(submitter, previousText) {
      submitter.disabled = false;
      submitter.textContent = previousText;
    }

    document.querySelectorAll('form[data-js-action]').forEach((form) => {
      let action = form.getAttribute('data-js-action');
      let isDownloadable = form.getAttribute('data-js-downloadable') === 'true';
      form.addEventListener('submit', (e) => {
        e.preventDefault();
        let formData = new FormData(form);
        let jsonData = {};
        formData.forEach((value, key) => {
          jsonData[key] = value;
        });

        // disable the submitter while processing
        let submitter = e.submitter;
        let previousText = submitter.textContent;
        submitter.disabled = true;
        submitter.textContent = submitter.getAttribute('data-js-submit') || 'Sending...';

        fetch(action, {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify(jsonData)
        }).then(async (res) => {
          if(res.status == 404) {
            if(opts.on404) opts.on404();
          } else if(res.status == 400) {
            if(opts.on400) opts.on400();
          } else if(res.status == 500) {
            if(opts.on500) opts.on500();
          }

          if(!res.ok) {
            resetSubmitter(submitter, previousText);
            return;
          }
          
          if (isDownloadable) {
            // Get filename from Content-Disposition header
            const disposition = res.headers.get('Content-Disposition');
            let filename = 'downloaded_file';
            if (disposition && disposition.includes('filename=')) {
              filename = disposition.split('filename=')[1].replace(/["']/g, '');
            }
            const blob = await res.blob();
            const url = window.URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = filename;
            document.body.appendChild(a);
            a.click();
            a.remove();
            window.URL.revokeObjectURL(url);
          } else {
            let data = await res.json();
            if(opts.on200) opts.on200({
              submitter: submitter,
              responseData: data
            });
          }
          
          if(!opts.on200)
            setTimeout(() => {
              resetSubmitter(submitter, previousText);
            }, 500);
        });
      });
    });
  }
}

/**
 * Slug Inline Editor
 * Allows inline editing of slugs with basic formatting
 */
export const Slug = {
  init: () => {
    document.querySelectorAll('[data-sunday-target]').forEach(function(el) {
      var editingState = {
        isEditing: false,
        inputElement: null,
        cancelButton: null
      }

      el.addEventListener('click', function(e) {
        e.preventDefault();
        
        let element = document.querySelector(el.getAttribute('data-sunday-target'));

        if (editingState.isEditing) {
          editingState.inputElement.value = editingState.inputElement.value.replace(/^-+|-+$/g, '');
          element.textContent = editingState.inputElement.value;
          element.style.display = 'inline';
          el.textContent = 'Edit';
          editingState.isEditing = false;
          editingState.inputElement.remove();
          editingState.cancelButton.remove();
          return;
        }
        
        const input = document.createElement('input');
        input.type = 'text';
        input.value = element.textContent;
        input.className = 'form-control form-control-sm py-0 px-2 rounded-3 d-inline-block w-50';

        element.insertAdjacentElement('afterend', input);
        element.style.display = 'none';
        el.textContent = 'Save';

        // add a `cancel` button after the save button
        editingState.cancelButton = document.createElement('button');
        editingState.cancelButton.className = 'btn btn-sm ms-2 border-0';
        editingState.cancelButton.textContent = 'Cancel';
        el.insertAdjacentElement('afterend', editingState.cancelButton);

        editingState.cancelButton.addEventListener('click', function() {
          input.remove();
          element.style.display = 'inline';
          el.textContent = 'Edit';
          editingState.cancelButton.remove();
          editingState.isEditing = false;
        });

        input.focus();
        editingState.isEditing = true;
        editingState.inputElement = input;

        input.addEventListener('keydown', function(event) {
          if (event.key === 'Enter') {
            const newText = input.value;
            input.remove();
            element.style.display = 'inline';
            element.textContent = newText;
            el.textContent = 'Edit';
            editingState.cancelButton.remove();
          } else if (event.key === 'Escape') {
            input.remove();
            element.style.display = 'inline';
            el.textContent = 'Edit';
            editingState.cancelButton.remove();
            editingState = { isEditing: false, inputElement: null, cancelButton: null}
          }
        });

        input.addEventListener('input', function() {
          // Format the slug: lowercase, replace spaces, remove special chars
          let formattedText = input.value
            .toLowerCase()
            .replace(/\s+/g, '-')
            .replace(/[^a-z0-9\-]/g, '');
          if (input.value !== formattedText) {
            input.value = formattedText;
          }
        });
      });
    });
  }
}