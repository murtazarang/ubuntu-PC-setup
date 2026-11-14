Build a small, polished website for a fictional neighborhood coffee shop named Maple & Main.

Use the free AstroWind starter:
https://github.com/arthelokyo/astrowind

The finished website must have three separate pages: Home, Menu, and Visit. This is a static website: do not add a database, login, payment system, or backend.

Work through the following steps in order. Do not skip the build check.

STEP 1: SET UP THE PROJECT

1. Create a new project folder named maple-main-site in the current working directory. Do not modify other projects.
2. Clone or download the AstroWind repository into that folder.
3. Read the project’s README and inspect its package.json. Use the project’s documented package manager and commands to install dependencies.
4. Keep the repository’s license and any required attribution.
5. Inspect the existing page files, shared layouts, navigation, and reusable components. Follow the project’s existing structure instead of replacing its configuration with a new one.

STEP 2: APPLY A CONSISTENT DESIGN

The shop should feel welcoming, calm, and modern. Use the following design decisions throughout the site:

- Page background: warm cream (#F7F3EB).
- Main text and headings: dark coffee brown (#32251E).
- Buttons and small accents: muted forest green (#58715B), with white button text.
- Cards or section backgrounds: white or a slightly darker cream.
- Use a clean, readable sans-serif body font. Headings should be noticeably larger and bolder than body text.
- Center content in a container with a maximum width of about 1100 pixels. Leave generous space around sections.
- Use rounded corners on buttons and cards, and subtle borders or shadows. Avoid heavy animation and bright gradients.
- Use the template’s existing icons or simple CSS shapes. Do not require paid images, remote image services, or new image downloads.

Use the existing AstroWind layout and components where appropriate. Add or change CSS only as needed. Do not leave template branding, unrelated starter text, or broken image placeholders on the pages you change.

STEP 3: CREATE SHARED NAVIGATION AND FOOTER

Create or adapt a shared header so all three pages show:
- “Maple & Main” on the left, linked to Home.
- Links labeled Home, Menu, and Visit, in that order, pointing to /, /menu, and /visit.
- On a narrow phone screen, keep the links readable and usable. A simple stacked or wrapped navigation is acceptable; a complex mobile menu is not required.

Create a shared footer with:
- “Maple & Main” and the phrase “A fictional neighborhood coffee shop.”
- Links to Home, Menu, and Visit.
- “Example website — not a real business.”

STEP 4: BUILD THE HOME PAGE (/)

Arrange the page in this order:

1. Hero section:
   - Small introductory label: “YOUR NEIGHBORHOOD COFFEE SHOP”.
   - Main heading: “Good coffee, good company.”
   - Supporting text: “Take a break, find your favorite drink, and make yourself at home.”
   - A green button labeled “View the Menu” linking to /menu.
   - Give this section generous vertical space. A simple decorative coffee-cup illustration or colored shape is optional; do not block the text.

2. Featured drinks section:
   - Heading: “A few favorites”.
   - Show three equal-sized cards on desktop and stack them on mobile.
   - Card 1: “Espresso” — “A rich, smooth shot.” — “$3.00”.
   - Card 2: “Cappuccino” — “Espresso with steamed milk and foam.” — “$4.50”.
   - Card 3: “Green Tea” — “A light and refreshing cup.” — “$3.50”.

3. Visit section:
   - Heading: “Come say hello”.
   - Text: “Find a comfortable seat and enjoy a little time for yourself.”
   - Button labeled “Plan Your Visit” linking to /visit.

STEP 5: BUILD THE MENU PAGE (/menu)

- Start with the heading “Our Menu” and the text “Simple drinks, made with care.”
- Add a Coffee section listing Espresso $3.00, Cappuccino $4.50, and Latte $5.00.
- Add a Tea section listing Black Tea $3.00 and Green Tea $3.50.
- Present each item’s name and price clearly, using the same card or list styling throughout. On small screens, prevent names and prices from overlapping.
- End with a link labeled “Visit the shop” pointing to /visit.

STEP 6: BUILD THE VISIT PAGE (/visit)

- Start with the heading “Visit Us” and the text “We look forward to welcoming you.”
- Show an Address card: “123 Maple Street, Springfield, USA.”
- Show an Hours card: “Monday–Friday: 7 AM–5 PM” and “Saturday–Sunday: 8 AM–4 PM.”
- Put the cards side by side on desktop and stack them on mobile.
- Below the cards, state clearly: “Maple & Main and this address are fictional.”
- Do not add a real map, phone number, email address, or contact form.

STEP 7: CHECK THE RESULT

1. Confirm the pages are separate routes, not three sections on one page.
2. Check every header, footer, and button link against the routes listed above.
3. Check that each page has one clear main heading and readable text contrast. Ensure buttons and links can be reached by keyboard.
4. Check that layouts do not overflow on a narrow screen. If a browser is available, inspect all three pages at desktop and phone widths. If not, inspect the responsive CSS and say browser testing was unavailable.
5. Run the production build command from the README or package.json. If it fails, read the error, fix the cause, and rerun the build.

STEP 8: REPORT

Tell me which files you created or changed, the command to run the site locally, whether the build passed, and whether you actually tested the site in a browser. If you cannot complete a step, give the exact error and stop. Do not claim that an unperformed test passed.
