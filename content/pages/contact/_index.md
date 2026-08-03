---
title: "Contact"
description: "Contact Five Minutes Tech for questions, collaborations, or feedback"
date: 2025-01-01
draft: false
unsafe: true
---

### Contact Five Minutes Tech

Have a question, collaboration idea, or tutorial request?  
We’d love to hear from you!

📧 **Email:** [blog@sourish4c.com](mailto:blog@sourish4c.com)  
🐦 **X (Twitter):** [@sourish4c](https://x.com/sourish4c)  
💼 **LinkedIn:** [@sourish4c](https://www.linkedin.com/in/sourish4c)

You can also suggest topics you'd like us to cover — AI, DevOps, Home Lab, or anything tech in between.

{{< alert "twitter" >}}
Thanks for reaching out. Talk soon. 🚀
{{< /alert >}}

---
<div class="flex justify-center py-8">
  <div class="w-full max-w-md bg-primary-50 dark:bg-neutral-800 border border-primary-100 dark:border-neutral-700 p-6 rounded-lg shadow-sm">
    <p class="text-center text-neutral-600 dark:text-neutral-400 mb-6">
      Fill up the form below to send us a message.
    </p>
    <form action="https://api.web3forms.com/submit" method="POST" id="contact-form">
      <input type="hidden" name="access_key" value="YOUR_ACCESS_KEY_HERE" />
      <input
        type="hidden"
        name="subject"
        value="New Submission from 5 Minutes Tech"/>
      <input
        type="hidden"
        name="redirect"
        value="https://blog.sourish4c.com/pages/contact/thank-you/"/>
      <input type="checkbox" name="botcheck" id="" style="display: none;" />
      <div class="mb-5">
        <label
          for="name"
          class="block mb-2 text-sm font-medium text-neutral-700 dark:text-neutral-300"
          >Full Name</label>
        <input
          type="text"
          name="name"
          id="name"
          placeholder="John Doe"
          required
          class="w-full px-3 py-2 bg-neutral dark:bg-neutral-900 border border-primary-200 dark:border-neutral-700 rounded-md text-neutral-800 dark:text-neutral-100 placeholder-neutral-400 dark:placeholder-neutral-500 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500 dark:focus:ring-primary-700 dark:focus:border-primary-500 transition-colors"/>
      </div>
      <div class="mb-5">
        <label
          for="email"
          class="block mb-2 text-sm font-medium text-neutral-700 dark:text-neutral-300"
          >Email Address</label>
        <input
          type="email"
          name="email"
          id="email"
          placeholder="you@company.com"
          required
          class="w-full px-3 py-2 bg-neutral dark:bg-neutral-900 border border-primary-200 dark:border-neutral-700 rounded-md text-neutral-800 dark:text-neutral-100 placeholder-neutral-400 dark:placeholder-neutral-500 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500 dark:focus:ring-primary-700 dark:focus:border-primary-500 transition-colors"
        />
      </div>
      <div class="mb-5">
        <label for="phone" class="block mb-2 text-sm font-medium text-neutral-700 dark:text-neutral-300"
          >Phone Number <span class="text-neutral-500 dark:text-neutral-500 font-normal">(optional)</span></label
        >
        <input
          type="text"
          name="phone"
          id="phone"
          placeholder="+1 (555) 1234-567"
          class="w-full px-3 py-2 bg-neutral dark:bg-neutral-900 border border-primary-200 dark:border-neutral-700 rounded-md text-neutral-800 dark:text-neutral-100 placeholder-neutral-400 dark:placeholder-neutral-500 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500 dark:focus:ring-primary-700 dark:focus:border-primary-500 transition-colors"
        />
      </div>
      <div class="mb-6">
        <label
          for="message"
          class="block mb-2 text-sm font-medium text-neutral-700 dark:text-neutral-300"
          >Your Message</label><textarea
          rows="5"
          name="message"
          id="message"
          placeholder="Your Message"
          class="w-full px-3 py-2 bg-neutral dark:bg-neutral-900 border border-primary-200 dark:border-neutral-700 rounded-md text-neutral-800 dark:text-neutral-100 placeholder-neutral-400 dark:placeholder-neutral-500 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500 dark:focus:ring-primary-700 dark:focus:border-primary-500 transition-colors"
          required
        ></textarea>
      </div>
      <div class="mb-4">
        <button
          type="submit"
          class="w-full px-3 py-3 bg-primary-600 hover:bg-primary-500 dark:bg-primary-700 dark:hover:bg-primary-600 text-neutral font-semibold rounded-md focus:outline-none focus:ring-2 focus:ring-primary-300 dark:focus:ring-primary-700 transition-colors"
          >Send Message</button>
      </div>
      <p class="text-base text-center text-neutral-500 dark:text-neutral-400" id="result"></p>
    </form>
  </div>
</div>

<script>
  (function () {
    var form = document.getElementById('contact-form');
    if (!form) return;
    var result = document.getElementById('result');
    var submitBtn = form.querySelector('button[type="submit"]');
    var originalBtnText = submitBtn ? submitBtn.textContent : 'Send Message';

    function setResult(message, kind) {
      if (!result) return;
      result.textContent = message;
      var base = 'text-base text-center mt-4 ';
      if (kind === 'error') {
        result.className = base + 'text-red-600 dark:text-red-400';
      } else if (kind === 'pending') {
        result.className = base + 'text-neutral-600 dark:text-neutral-400';
      } else {
        result.className = base + 'text-neutral-500 dark:text-neutral-400';
      }
    }

    form.addEventListener('submit', async function (e) {
      e.preventDefault();

      var accessKey = form.querySelector('input[name="access_key"]').value;
      if (!accessKey || accessKey === 'YOUR_ACCESS_KEY_HERE') {
        setResult('Form is not configured yet. Please email blog@sourish4c.com instead.', 'error');
        return;
      }

      if (submitBtn) {
        submitBtn.disabled = true;
        submitBtn.textContent = 'Sending...';
      }
      setResult('Sending your message...', 'pending');

      try {
        var formData = new FormData(form);
        var response = await fetch('https://api.web3forms.com/submit', {
          method: 'POST',
          body: formData,
          headers: { 'Accept': 'application/json' }
        });
        var data = await response.json().catch(function () { return {}; });

        if (response.ok && data.success) {
          window.location.href = '/pages/contact/thank-you/';
          return;
        }

        setResult(
          (data && data.message) || 'Something went wrong. Please try again or email blog@sourish4c.com.',
          'error'
        );
      } catch (err) {
        setResult('Network error. Please check your connection and try again.', 'error');
      } finally {
        if (submitBtn) {
          submitBtn.disabled = false;
          submitBtn.textContent = originalBtnText;
        }
      }
    });
  })();
</script>

---
