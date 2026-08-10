# GE.motion

GE.motion is a web application that enables users to create personalized videos by collaborating with friends and family. It allows for the creation of video tributes with personalized chapters, dedicatory messages, and music selections.

## Project Links

- **Repository**: [GitHub](https://github.com/Maxime-Potier/gemotion)
- **Design**:
  - [V1 Figma](https://www.figma.com/design/jbjqYggXQE9sfcARvV4jMN/GE.motion-(V1)?node-id=17-268)
  - [MVP Figma](https://www.figma.com/design/ME2zLN3ohSOVdtNTTMqmRT/GE.motion-(MVP)?node-id=17-268)
- **Translations**: [Google Sheets](https://docs.google.com/spreadsheets/d/1jHDoZdavTQnwkXQkzY9lEaY78rENtSLdHrtYYbhStAo/edit?usp=sharing)

## Tech Stack

- Ruby on Rails
- Stimulus.js
- Tailwind CSS
- PostgreSQL
- Active Storage for file uploads
- Sidekiq with Redis for background processing
- FFmpeg for video processing
- ffmpeg-concat for complex GL transitions (https://github.com/transitive-bullshit/ffmpeg-concat)

## Contributing as a Developer

### Local Docker review

The production-like local stack includes Rails, Sidekiq, PostgreSQL, and Redis:

```sh
docker compose up --build
```

Open `http://127.0.0.1:3300`. The local Compose configuration explicitly uses
plain HTTP; it does not redirect to HTTPS. Stop the stack with
`docker compose down`. Add `--volumes` only when you intentionally want to
delete the local PostgreSQL data and uploaded files.

### 1. Setting Up the Development Environment

1. Creata a fork in your repository of Github

2. Clone the repository:
   ```
   git clone https://github.com/{your repository}/gemotion.git
   cd gemotion
   ```

3. Install dependencies:
   ```
   bundle install
   ```

4. Set up the database:
   ```
   rails db:create db:migrate db:seed
   ```

5. Start the development server:
   ```
   bin/dev
   ```

### Gmail invitation emails

Development continues to use `letter_opener` unless Gmail credentials are provided. Copy `.env.example` to the ignored `.env` file and configure these values before starting Rails and Sidekiq:

```sh
cp .env.example .env
```

`GMAIL_APP_PASSWORD` must be a Google App Password, not the normal account password. The Google account must have two-step verification enabled. For a local server exposed through a temporary tunnel, set `APP_HOST` to the tunnel hostname without `https://` and restart both Rails and Sidekiq whenever the hostname changes.

### 2. Making Contributions

#### Creating an Issue

1. Go to the [repository's Issues page](https://github.com/Maxime-Potier/gemotion/issues)
2. Click "New Issue"
3. Select the appropriate issue template if available
4. Fill in the required information:
   - Title: A clear, concise title describing the issue
   - Description: Detailed information about the problem or feature, including steps to reproduce if relevant
   - Labels: Add relevant labels (bug, enhancement, documentation, etc.)
   - Assignees: Assign yourself or leave blank
5. Submit the issue

#### Working on a Feature/Bug Fix

1. Create a new branch from the main branch:
   ```
   git checkout main
   git pull origin main
   git checkout -b your-feature-name
   ```
   Use a descriptive branch name, e.g., `video-sharing` or `login-error`

2. Make your changes, following these guidelines:
   - Follow the existing code style
   - Write clean, readable code
   - Include comments where appropriate

3. Commit your changes with clear, descriptive commit messages:
   ```
   git add .
   git commit -m "Add feature: description of what you did"
   ```

4. Push your branch to GitHub:
   ```
   git push origin feature/your-feature-name
   ```

#### Creating a Pull Request

1. Go to the [repository's Pull Requests page](https://github.com/Maxime-Potier/gemotion/pulls)
2. Click "New Pull Request"
3. Select your branch as the compare branch and main as the base branch
4. Fill in the required information:
   - Title: A clear title describing your changes
   - Description: Include details about what you've changed and why
   - Reference any related issues using the GitHub issue linking syntax (e.g., "Fixes #123")
5. Request a review from a maintainer
6. Submit the pull request
7. After finisih the Pull Request squash the commits to one commit:
   - git reset --soft {first commit of pull request}~1
   - git add .
   - git commit -m "Description of First commit of PR" 
   - git push -f
   - NOTE: If you Merged a Branch between the commits your are squashing you will need to make the Merge after the Squash


#### Code Review Process

1. Wait for a maintainer to review your code
2. Address any feedback or requested changes
3. Once approved, your changes will be merged into the main branch
