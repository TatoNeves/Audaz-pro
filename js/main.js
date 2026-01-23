/* ===================================
   AUDAZ PRO - Main JavaScript
   =================================== */

document.addEventListener('DOMContentLoaded', function() {
  
  // Mobile Menu Toggle
  const mobileToggle = document.querySelector('.mobile-toggle');
  const nav = document.querySelector('.nav');
  
  if (mobileToggle) {
    mobileToggle.addEventListener('click', function() {
      nav.classList.toggle('active');
      this.classList.toggle('active');
    });
  }
  
  // Close mobile menu when clicking on a link
  const navLinks = document.querySelectorAll('.nav-link');
  navLinks.forEach(link => {
    link.addEventListener('click', function() {
      nav.classList.remove('active');
      if (mobileToggle) {
        mobileToggle.classList.remove('active');
      }
    });
  });
  
  // Header scroll effect
  const header = document.querySelector('.header');
  let lastScroll = 0;
  
  window.addEventListener('scroll', function() {
    const currentScroll = window.pageYOffset;
    
    if (currentScroll > 100) {
      header.style.boxShadow = '0 2px 20px rgba(0, 0, 0, 0.2)';
    } else {
      header.style.boxShadow = 'none';
    }
    
    lastScroll = currentScroll;
  });
  
  // Scroll Reveal Animation
  const revealElements = document.querySelectorAll('.reveal');
  
  function reveal() {
    revealElements.forEach(element => {
      const windowHeight = window.innerHeight;
      const elementTop = element.getBoundingClientRect().top;
      const elementVisible = 150;
      
      if (elementTop < windowHeight - elementVisible) {
        element.classList.add('active');
      }
    });
  }
  
  window.addEventListener('scroll', reveal);
  reveal(); // Initial check
  
  // Smooth scroll for anchor links
  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function(e) {
      const href = this.getAttribute('href');
      if (href !== '#') {
        e.preventDefault();
        const target = document.querySelector(href);
        if (target) {
          target.scrollIntoView({
            behavior: 'smooth',
            block: 'start'
          });
        }
      }
    });
  });
  
  // Active navigation link based on current page
  const currentPage = window.location.pathname.split('/').pop() || 'index.html';
  const navMenuLinks = document.querySelectorAll('.nav-link');
  
  navMenuLinks.forEach(link => {
    const linkHref = link.getAttribute('href');
    if (linkHref === currentPage || 
        (currentPage === '' && linkHref === 'index.html') ||
        (currentPage === 'index.html' && linkHref === 'index.html')) {
      link.classList.add('active');
    }
  });

});

/* ===================================
   CONTACT FORM HANDLER
   =================================== */

const CONTACT_TABLE = 'contacts';

async function handleContactForm(event) {
  event.preventDefault();

  const form = event.target;
  const submitBtn = form.querySelector('button[type="submit"]');
  const originalText = submitBtn.textContent;

  const formData = new FormData(form);
  const name = formData.get('name');
  const email = formData.get('email');
  const message = formData.get('message');

  if (!name || !email || !message) {
    showFormMessage('Please fill in all required fields.', 'error');
    return;
  }

  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(email)) {
    showFormMessage('Please enter a valid email address.', 'error');
    return;
  }

  submitBtn.disabled = true;
  submitBtn.textContent = 'Sending...';

  if (typeof AudazSupabase === 'undefined' || !AudazSupabase.isConfigured()) {
    showFormMessage('Supabase is not configured. Update js/supabase-config.js with your project credentials.', 'error');
    submitBtn.disabled = false;
    submitBtn.textContent = originalText;
    return;
  }

  const client = AudazSupabase.getClient();
  if (!client) {
    showFormMessage('Unable to initialize Supabase client. Please try again later.', 'error');
    submitBtn.disabled = false;
    submitBtn.textContent = originalText;
    return;
  }

  const payload = {
    name,
    company: formData.get('company') || null,
    email,
    phone: formData.get('phone') || null,
    budget: formData.get('budget') || null,
    message
  };

  try {
    const { error } = await client.from(CONTACT_TABLE).insert(payload);

    if (error) {
      throw error;
    }

    showFormMessage('Thank you! Your message has been sent successfully.', 'success');
    form.reset();
  } catch (error) {
    console.error('Form submission error:', error);
    const friendlyMsg = error?.message || 'Sorry, there was an error sending your message. Please try again.';
    showFormMessage(friendlyMsg, 'error');
  } finally {
    submitBtn.disabled = false;
    submitBtn.textContent = originalText;
  }
}

function showFormMessage(message, type) {
  // Remove existing message
  const existingMessage = document.querySelector('.form-message');
  if (existingMessage) {
    existingMessage.remove();
  }
  
  // Create message element
  const messageEl = document.createElement('div');
  messageEl.className = `form-message form-message-${type}`;
  messageEl.textContent = message;
  messageEl.style.cssText = `
    padding: 1rem;
    margin-top: 1rem;
    border-radius: 8px;
    text-align: center;
    font-weight: 500;
    ${type === 'success' 
      ? 'background-color: #d4edda; color: #155724; border: 1px solid #c3e6cb;' 
      : 'background-color: #f8d7da; color: #721c24; border: 1px solid #f5c6cb;'}
  `;
  
  // Insert after form
  const form = document.querySelector('.contact-form');
  form.appendChild(messageEl);
  
  // Auto remove after 5 seconds
  setTimeout(() => {
    messageEl.remove();
  }, 5000);
}

/* ===================================
   UTILITY FUNCTIONS
   =================================== */

// Debounce function for scroll events
function debounce(func, wait = 20, immediate = true) {
  let timeout;
  return function() {
    const context = this, args = arguments;
    const later = function() {
      timeout = null;
      if (!immediate) func.apply(context, args);
    };
    const callNow = immediate && !timeout;
    clearTimeout(timeout);
    timeout = setTimeout(later, wait);
    if (callNow) func.apply(context, args);
  };
}

// Intersection Observer for lazy loading
const lazyImages = document.querySelectorAll('img[data-src]');

if ('IntersectionObserver' in window) {
  const imageObserver = new IntersectionObserver((entries, observer) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        const img = entry.target;
        img.src = img.dataset.src;
        img.removeAttribute('data-src');
        observer.unobserve(img);
      }
    });
  });
  
  lazyImages.forEach(img => imageObserver.observe(img));
}
