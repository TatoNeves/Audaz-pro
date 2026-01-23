/**
 * AUDAZ PRO - UI Components
 *
 * Reusable UI components for the ticket system
 */

const UIComponents = {
    // ============================================
    // Toast Notifications
    // ============================================
    showToast(message, type = 'info') {
        // Remove existing toasts
        const existing = document.querySelectorAll('.toast-notification');
        existing.forEach(t => t.remove());

        const toast = document.createElement('div');
        toast.className = `toast-notification toast-${type}`;
        toast.innerHTML = `
            <span class="toast-message">${message}</span>
            <button class="toast-close" onclick="this.parentElement.remove()">&times;</button>
        `;

        document.body.appendChild(toast);

        // Auto remove after 5 seconds
        setTimeout(() => {
            toast.classList.add('toast-fade-out');
            setTimeout(() => toast.remove(), 300);
        }, 5000);
    },

    showSuccess(message) {
        this.showToast(message, 'success');
    },

    showError(message) {
        this.showToast(message, 'error');
    },

    showWarning(message) {
        this.showToast(message, 'warning');
    },

    // ============================================
    // Loading States
    // ============================================
    showLoading(container, message = 'Loading...') {
        if (typeof container === 'string') {
            container = document.querySelector(container);
        }
        if (!container) return;

        container.innerHTML = `
            <div class="loading-state">
                <div class="loading-spinner"></div>
                <p>${message}</p>
            </div>
        `;
    },

    hideLoading(container) {
        if (typeof container === 'string') {
            container = document.querySelector(container);
        }
        if (!container) return;

        const loading = container.querySelector('.loading-state');
        if (loading) {
            loading.remove();
        }
    },

    // ============================================
    // Empty States
    // ============================================
    showEmptyState(container, { icon = 'inbox', title, message, actionText, actionHandler }) {
        if (typeof container === 'string') {
            container = document.querySelector(container);
        }
        if (!container) return;

        const icons = {
            inbox: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 9h18M9 21V9"/></svg>',
            ticket: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M15 5v2m0 4v2m0 4v2M5 5a2 2 0 0 0-2 2v3a2 2 0 1 1 0 4v3a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-3a2 2 0 1 1 0-4V7a2 2 0 0 0-2-2H5z"/></svg>',
            users: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/></svg>',
            search: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/></svg>'
        };

        const actionButton = actionText ? `<button class="btn btn-primary empty-state-action">${actionText}</button>` : '';

        container.innerHTML = `
            <div class="empty-state">
                <div class="empty-state-icon">${icons[icon] || icons.inbox}</div>
                <h3 class="empty-state-title">${title}</h3>
                <p class="empty-state-message">${message}</p>
                ${actionButton}
            </div>
        `;

        if (actionHandler) {
            const btn = container.querySelector('.empty-state-action');
            if (btn) {
                btn.addEventListener('click', actionHandler);
            }
        }
    },

    // ============================================
    // Ticket Status Badge
    // ============================================
    createStatusBadge(status) {
        const statusMap = {
            'open': { label: 'Open', class: 'status-open' },
            'in_progress': { label: 'In Progress', class: 'status-progress' },
            'done': { label: 'Done', class: 'status-done' },
            'cancelled': { label: 'Cancelled', class: 'status-cancelled' }
        };

        const statusInfo = statusMap[status] || { label: status, class: '' };
        return `<span class="status-badge ${statusInfo.class}">${statusInfo.label}</span>`;
    },

    // ============================================
    // Priority Badge
    // ============================================
    createPriorityBadge(priority) {
        const priorityMap = {
            'baixa': { label: 'Low', class: 'priority-low' },
            'media': { label: 'Normal', class: 'priority-medium' },
            'alta': { label: 'High', class: 'priority-high' },
            'urgente': { label: 'Urgent', class: 'priority-urgent' }
        };

        const priorityInfo = priorityMap[priority] || { label: priority, class: '' };
        return `<span class="priority-badge ${priorityInfo.class}">${priorityInfo.label}</span>`;
    },

    // ============================================
    // Type Badge
    // ============================================
    createTypeBadge(type) {
        const typeMap = {
            'alteracao': { label: 'Change Request', class: 'type-change' },
            'suporte': { label: 'Support', class: 'type-support' }
        };

        const typeInfo = typeMap[type] || { label: type, class: '' };
        return `<span class="type-badge ${typeInfo.class}">${typeInfo.label}</span>`;
    },

    // ============================================
    // Role Badge
    // ============================================
    createRoleBadge(role) {
        const roleMap = {
            'client_admin': { label: 'Admin', class: 'role-admin' },
            'client_user': { label: 'User', class: 'role-user' },
            'support_agent': { label: 'Support', class: 'role-support' },
            'support_admin': { label: 'Support Admin', class: 'role-support-admin' }
        };

        const roleInfo = roleMap[role] || { label: role, class: '' };
        return `<span class="role-badge ${roleInfo.class}">${roleInfo.label}</span>`;
    },

    // ============================================
    // Stats Card
    // ============================================
    createStatsCard({ label, value, icon, color = 'default' }) {
        return `
            <div class="stats-card stats-${color}">
                <div class="stats-icon">${icon || ''}</div>
                <div class="stats-content">
                    <span class="stats-value">${value}</span>
                    <span class="stats-label">${label}</span>
                </div>
            </div>
        `;
    },

    // ============================================
    // Format Date
    // ============================================
    formatDate(dateString, options = {}) {
        const date = new Date(dateString);
        const now = new Date();
        const diff = now - date;
        const diffDays = Math.floor(diff / (1000 * 60 * 60 * 24));
        const diffHours = Math.floor(diff / (1000 * 60 * 60));
        const diffMinutes = Math.floor(diff / (1000 * 60));

        if (options.relative !== false) {
            if (diffMinutes < 1) return 'Now';
            if (diffMinutes < 60) return `${diffMinutes}m ago`;
            if (diffHours < 24) return `${diffHours}h ago`;
            if (diffDays < 7) return `${diffDays}d ago`;
        }

        return date.toLocaleDateString('en-US', {
            day: '2-digit',
            month: '2-digit',
            year: 'numeric',
            hour: options.showTime !== false ? '2-digit' : undefined,
            minute: options.showTime !== false ? '2-digit' : undefined
        });
    },

    // ============================================
    // Confirm Dialog
    // ============================================
    async confirm(message, title = 'Confirm') {
        return new Promise(resolve => {
            const overlay = document.createElement('div');
            overlay.className = 'modal-overlay';
            overlay.innerHTML = `
                <div class="modal-dialog">
                    <h3 class="modal-title">${title}</h3>
                    <p class="modal-message">${message}</p>
                    <div class="modal-actions">
                        <button class="btn btn-secondary modal-cancel">Cancel</button>
                        <button class="btn btn-primary modal-confirm">Confirm</button>
                    </div>
                </div>
            `;

            document.body.appendChild(overlay);

            overlay.querySelector('.modal-cancel').addEventListener('click', () => {
                overlay.remove();
                resolve(false);
            });

            overlay.querySelector('.modal-confirm').addEventListener('click', () => {
                overlay.remove();
                resolve(true);
            });

            overlay.addEventListener('click', (e) => {
                if (e.target === overlay) {
                    overlay.remove();
                    resolve(false);
                }
            });
        });
    },

    // ============================================
    // Ticket List Item
    // ============================================
    createTicketListItem(ticket, options = {}) {
        const baseUrl = options.isSupport ? '/support/tickets' : '/client/tickets';

        return `
            <a href="${baseUrl}/detail.html?id=${ticket.id}" class="ticket-list-item">
                <div class="ticket-list-main">
                    <div class="ticket-list-header">
                        ${this.createTypeBadge(ticket.type)}
                        ${this.createPriorityBadge(ticket.priority)}
                        ${this.createStatusBadge(ticket.status)}
                    </div>
                    <h4 class="ticket-list-title">${this.escapeHtml(ticket.title)}</h4>
                    <p class="ticket-list-desc">${this.escapeHtml(ticket.description.substring(0, 120))}${ticket.description.length > 120 ? '...' : ''}</p>
                </div>
                <div class="ticket-list-meta">
                    ${options.showOrg && ticket.organization ? `<span class="ticket-org">${this.escapeHtml(ticket.organization.name)}</span>` : ''}
                    <span class="ticket-author">By ${this.escapeHtml(ticket.creator?.full_name || 'Unknown')}</span>
                    <span class="ticket-date">${this.formatDate(ticket.last_activity_at || ticket.created_at)}</span>
                </div>
            </a>
        `;
    },

    // ============================================
    // Ticket Comment
    // ============================================
    createCommentItem(comment, options = {}) {
        const context = options.context || {};
        const mentionableUsers = context.mentionableUsers || [];
        const parsed = this.parseCommentBody(comment.body || '', mentionableUsers);
        const isSupport = comment.author?.role?.startsWith('support');
        const roleLabel = isSupport ? 'Support' : 'Client';

        // Separate images from other attachments
        const imageAttachments = parsed.attachments.filter(att => att.isImage && att.url);
        const fileAttachments = parsed.attachments.filter(att => !att.isImage || !att.url);

        // Render image thumbnails
        const imagesHtml = imageAttachments.length > 0 ? `
            <div class="comment-images">
                ${imageAttachments.map(att => `
                    <a href="${this.escapeHtml(att.url)}" target="_blank" class="comment-image-thumb" title="${this.escapeHtml(att.name)}">
                        <img src="${this.escapeHtml(att.url)}" alt="${this.escapeHtml(att.name)}" loading="lazy">
                        <span class="image-overlay">
                            <span class="image-name">${this.escapeHtml(att.name)}</span>
                            ${att.size ? `<span class="image-size">${this.escapeHtml(att.size)}</span>` : ''}
                        </span>
                    </a>
                `).join('')}
            </div>
        ` : '';

        // Render file attachments as chips/links
        const filesHtml = fileAttachments.length > 0 ? `
            <div class="comment-attachments">
                ${fileAttachments.map(att => att.url ? `
                    <a href="${this.escapeHtml(att.url)}" target="_blank" class="comment-attachment-chip comment-attachment-link">
                        <span class="chip-icon">📎</span>
                        <span class="chip-name">${this.escapeHtml(att.name)}</span>
                        ${att.size ? `<span class="chip-size">${this.escapeHtml(att.size)}</span>` : ''}
                    </a>
                ` : `
                    <span class="comment-attachment-chip">
                        <span class="chip-icon">📎</span>
                        <span class="chip-name">${this.escapeHtml(att.name)}</span>
                    </span>
                `).join('')}
            </div>
        ` : '';

        return `
            <article class="comment-item ${isSupport ? 'comment-support' : 'comment-client'}">
                <div class="comment-avatar">${this.escapeHtml(this.getInitials(comment.author?.full_name || 'User'))}</div>
                <div class="comment-content">
                    <div class="comment-header">
                        <span class="comment-author">${this.escapeHtml(comment.author?.full_name || 'Unknown')}</span>
                        <span class="comment-role">${roleLabel}</span>
                        <span class="comment-date">${this.formatDate(comment.created_at)}</span>
                    </div>
                    ${parsed.bodyHtml ? `<div class="comment-body">${parsed.bodyHtml}</div>` : ''}
                    ${imagesHtml}
                    ${filesHtml}
                </div>
            </article>
        `;
    },

    parseCommentBody(body, mentionableUsers = []) {
        // Pattern to match: 📎 [filename](url) (size) or just 📎 filename
        const attachmentPattern = /📎\s*(?:\[([^\]]+)\]\(([^)]+)\)\s*\(([^)]+)\)|([^\n]+))/g;
        const attachments = [];
        const cleanedBody = (body || '').replace(attachmentPattern, (match, name, url, size, plainName) => {
            if (name && url) {
                // Markdown link format: [name](url) (size)
                attachments.push({
                    name: name.trim(),
                    url: url.trim(),
                    size: size ? size.trim() : null,
                    isImage: this.isImageUrl(url) || this.isImageFilename(name)
                });
            } else if (plainName) {
                // Plain text format (legacy)
                attachments.push({
                    name: plainName.trim(),
                    url: null,
                    size: null,
                    isImage: false
                });
            }
            return '';
        });

        // Handle both old format @[name|id] and new format @name
        const mentionChips = [];
        let processedBody = cleanedBody;

        // First, handle old format @[name|id]
        const oldMentionPattern = /@\[([^\]]+)\]/g;
        processedBody = processedBody.replace(oldMentionPattern, (match, raw) => {
            const parts = raw.split('|');
            const label = parts[0].trim();
            const id = parts[1]?.trim() || '';
            const matchedUser = mentionableUsers.find(user => user.id === id || user.full_name === label);
            const displayLabel = matchedUser?.full_name || label;
            const initials = this.getInitials(displayLabel);

            mentionChips.push({ label: displayLabel, initials });
            return `__MENTION__${displayLabel}__ENDMENTION__`;
        });

        // Then, handle new format @name (match against known users)
        if (mentionableUsers.length > 0) {
            // Sort by name length (longest first) to match "John Noss" before "John"
            const sortedUsers = [...mentionableUsers].sort((a, b) =>
                (b.full_name || '').length - (a.full_name || '').length
            );

            for (const user of sortedUsers) {
                if (!user.full_name) continue;
                const escapedName = user.full_name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                const newMentionPattern = new RegExp(`@${escapedName}(?![\\w])`, 'g');
                processedBody = processedBody.replace(newMentionPattern, (match) => {
                    const initials = this.getInitials(user.full_name);
                    // Only add to chips if not already added
                    if (!mentionChips.some(c => c.label === user.full_name)) {
                        mentionChips.push({ label: user.full_name, initials });
                    }
                    return `__MENTION__${user.full_name}__ENDMENTION__`;
                });
            }
        }

        // Now process the body: escape HTML, add line breaks, linkify, then restore mentions
        const escaped = this.escapeHtml(processedBody);
        const withLineBreaks = escaped.replace(/\n/g, '<br>');
        const linkified = this.linkify(withLineBreaks);

        // Restore mention placeholders to styled spans
        const processed = [linkified.replace(/__MENTION__([^_]+)__ENDMENTION__/g, (match, name) => {
            return `<span class="comment-mention-inline">@${this.escapeHtml(name)}</span>`;
        })];

        return {
            bodyHtml: processed.join(''),
            mentionChips,
            attachments: attachments.filter(Boolean)
        };
    },

    isImageUrl(url) {
        if (!url) return false;
        const imageExtensions = /\.(jpg|jpeg|png|gif|webp|svg|bmp)(\?.*)?$/i;
        return imageExtensions.test(url);
    },

    isImageFilename(filename) {
        if (!filename) return false;
        const imageExtensions = /\.(jpg|jpeg|png|gif|webp|svg|bmp)$/i;
        return imageExtensions.test(filename);
    },

    formatFileSize(bytes) {
        if (!bytes || bytes === 0) return '';
        const units = ['B', 'KB', 'MB', 'GB'];
        const exponent = Math.min(units.length - 1, Math.floor(Math.log(bytes) / Math.log(1024)));
        const value = bytes / Math.pow(1024, exponent);
        return `${value.toFixed(1)} ${units[exponent]}`;
    },

    linkify(text) {
        const urlPattern = /(https?:\/\/[^\s<]+)/g;
        return text.replace(urlPattern, url => `<a href="${url}" target="_blank" rel="noopener noreferrer">${url}</a>`);
    },

    extractUrls(text) {
        if (!text) return [];
        const urlPattern = /(https?:\/\/[^\s]+)/g;
        const matches = text.match(urlPattern) || [];
        return [...new Set(matches)];
    },

    shortenUrl(url) {
        try {
            const parsed = new URL(url);
            const path = parsed.pathname !== '/' ? parsed.pathname.replace(/\/$/, '') : '';
            return `${parsed.hostname}${path}`;
        } catch (err) {
            return url;
        }
    },

    getInitials(value) {
        if (!value) return '';
        const words = value.trim().split(/\s+/);
        if (words.length === 1) {
            return words[0].charAt(0).toUpperCase();
        }
        return (words[0].charAt(0) + words[words.length - 1].charAt(0)).toUpperCase();
    },

    // ============================================
    // Timeline Event
    // ============================================
    createTimelineEvent(event) {
        const eventText = CommentsService.formatEvent(event);

        return `
            <div class="timeline-event">
                <div class="timeline-dot"></div>
                <div class="timeline-content">
                    <span class="timeline-text">${this.escapeHtml(eventText)}</span>
                    <span class="timeline-date">${this.formatDate(event.created_at)}</span>
                </div>
            </div>
        `;
    },

    // ============================================
    // Team Member Item
    // ============================================
    createTeamMemberItem(member, isCurrentUser = false) {
        return `
            <div class="team-member-item ${isCurrentUser ? 'is-current' : ''}">
                <div class="member-avatar">${member.full_name.charAt(0).toUpperCase()}</div>
                <div class="member-info">
                    <span class="member-name">${this.escapeHtml(member.full_name)} ${isCurrentUser ? '(You)' : ''}</span>
                    <span class="member-role">${InvitationsService.formatRole(member.role)}</span>
                </div>
                <span class="member-date">Since ${this.formatDate(member.created_at, { relative: false, showTime: false })}</span>
            </div>
        `;
    },

    // ============================================
    // Invitation Item
    // ============================================
    createInvitationItem(invitation) {
        const statusMap = {
            'pending': { label: 'Pending', class: 'invite-pending' },
            'accepted': { label: 'Accepted', class: 'invite-accepted' },
            'expired': { label: 'Expired', class: 'invite-expired' }
        };

        const statusInfo = statusMap[invitation.status] || statusMap.pending;

        return `
            <div class="invitation-item ${statusInfo.class}">
                <div class="invite-info">
                    <span class="invite-email">${this.escapeHtml(invitation.email)}</span>
                    <span class="invite-role">${InvitationsService.formatRole(invitation.role)}</span>
                </div>
                <div class="invite-meta">
                    <span class="invite-status">${statusInfo.label}</span>
                    ${invitation.status === 'pending' ? `
                        <button class="btn-icon copy-invite-link" data-token="${invitation.token}" title="Copy link">
                            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
                        </button>
                    ` : ''}
                </div>
            </div>
        `;
    },

    // ============================================
    // Escape HTML Helper
    // ============================================
    escapeHtml(str) {
        if (!str) return '';
        const div = document.createElement('div');
        div.textContent = str;
        return div.innerHTML;
    },

    // ============================================
    // Collaborators Card
    // ============================================
    createCollaboratorsCard(collaborators, options = {}) {
        const { canAdd = false, canRemove = false, availableUsers = [] } = options;

        const roleLabels = {
            creator: 'Requester',
            assignee: 'Assigned',
            mentioned: 'Mentioned',
            manual: 'Collaborator'
        };

        const roleColors = {
            creator: 'blue',
            assignee: 'green',
            mentioned: 'yellow',
            manual: 'gray'
        };

        const collaboratorsList = collaborators.map(collab => {
            const initials = this.getInitials(collab.full_name);
            const roleLabel = roleLabels[collab.role] || 'Collaborator';
            const roleColor = roleColors[collab.role] || 'gray';
            const canRemoveThis = canRemove && collab.role !== 'creator' && collab.role !== 'assignee';

            return `
                <div class="collaborator-item" data-user-id="${collab.user_id}" data-role="${collab.role}">
                    <div class="collaborator-avatar collaborator-avatar--${roleColor}" title="${this.escapeHtml(collab.full_name)}">${initials}</div>
                    <div class="collaborator-info">
                        <span class="collaborator-name">${this.escapeHtml(collab.full_name)}</span>
                        <span class="collaborator-role">${roleLabel}</span>
                    </div>
                    ${canRemoveThis ? `
                        <button class="collaborator-remove" data-user-id="${collab.user_id}" title="Remove collaborator">
                            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="16" height="16">
                                <line x1="18" y1="6" x2="6" y2="18"></line>
                                <line x1="6" y1="6" x2="18" y2="18"></line>
                            </svg>
                        </button>
                    ` : ''}
                </div>
            `;
        }).join('');

        // Group users by their group property (if present)
        const groupedUsers = {};
        const ungroupedUsers = [];
        availableUsers.forEach(user => {
            if (user.group) {
                if (!groupedUsers[user.group]) {
                    groupedUsers[user.group] = [];
                }
                groupedUsers[user.group].push(user);
            } else {
                ungroupedUsers.push(user);
            }
        });

        const hasGroups = Object.keys(groupedUsers).length > 0;
        let optionsHtml = '';

        if (hasGroups) {
            // Render with optgroups
            Object.keys(groupedUsers).forEach(groupName => {
                optionsHtml += `<optgroup label="${this.escapeHtml(groupName)}">`;
                groupedUsers[groupName].forEach(user => {
                    optionsHtml += `<option value="${user.id}">${this.escapeHtml(user.full_name)}</option>`;
                });
                optionsHtml += `</optgroup>`;
            });
            // Add ungrouped users at the end if any
            ungroupedUsers.forEach(user => {
                optionsHtml += `<option value="${user.id}">${this.escapeHtml(user.full_name)}</option>`;
            });
        } else {
            // Simple list without groups
            availableUsers.forEach(user => {
                optionsHtml += `<option value="${user.id}">${this.escapeHtml(user.full_name)}</option>`;
            });
        }

        const addDropdown = canAdd && availableUsers.length > 0 ? `
            <div class="collaborator-add">
                <select id="add-collaborator-select" class="collaborator-select">
                    <option value="">Add collaborator...</option>
                    ${optionsHtml}
                </select>
                <button type="button" id="add-collaborator-btn" class="btn btn-small btn-primary">Add</button>
            </div>
        ` : '';

        return `
            <div class="collaborators-list" id="collaborators-list">
                ${collaboratorsList || '<p class="no-collaborators">No collaborators yet</p>'}
            </div>
            ${addDropdown}
        `;
    },

    // ============================================
    // Button Loading State
    // ============================================
    setButtonLoading(button, loading = true, originalText = null) {
        if (typeof button === 'string') {
            button = document.querySelector(button);
        }
        if (!button) return;

        if (loading) {
            button.dataset.originalText = button.textContent;
            button.disabled = true;
            button.innerHTML = '<span class="btn-spinner"></span> Please wait...';
        } else {
            button.disabled = false;
            button.textContent = originalText || button.dataset.originalText || 'Send';
        }
    }
};

// Export
window.UIComponents = UIComponents;
