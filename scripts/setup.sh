#!/bin/bash

# Generate SSH key for deployments
echo -e "\nRunning setup ...\n"
mkdir -p ~/.ssh
echo "Generating SSH keys for deployments"
declare -r KEY_NAME="circle_ciwriteable_$(date +%s)"
ssh-keygen -f ~/.ssh/$KEY_NAME -C "CircleCI writeable" -m PEM -t rsa -q -N "" > /dev/null
declare KEY_FINGERPRINT=$(ssh-keygen -E md5 -lf ~/.ssh/$KEY_NAME)
KEY_FINGERPRINT=${KEY_FINGERPRINT#*MD5:}
readonly KEY_FINGERPRINT=${KEY_FINGERPRINT%% *}
declare PUBLIC_KEY=$(< ~/.ssh/$KEY_NAME.pub)
readonly PUBLIC_KEY=$(printf "%s" "$PUBLIC_KEY")
declare -r PRIVATE_KEY=$(< ~/.ssh/$KEY_NAME)

rm ~/.ssh/$KEY_NAME ~/.ssh/$KEY_NAME.pub
declare GIT_USERNAME="circleci"
declare GIT_EMAIL="circleci@iohk.io"

declare GITHUB_USERNAME=""
declare GITHUB_TOKEN=""
echo -e "\nEnter the GitHub username of the account you would like to use"
while [ -z "$GITHUB_USERNAME" ]; do
    read -p ": " GITHUB_USERNAME
done

echo -e "\nPlease now generate a personal access token with full repository access for ${GITHUB_USERNAME}:"
echo "https://help.github.com/en/articles/creating-a-personal-access-token-for-the-command-line"
echo -e "\nOpening https://github.com/settings/tokens/new\n"

read -p "Press enter to continue ..." any_key
open "https://github.com/settings/tokens/new"

echo -e "\nOnce you are done enter the token value here"
while [ -z "$GITHUB_TOKEN" ]; do
    read -p ": " GITHUB_TOKEN
done

# Getting CNAME
echo -e "\nWhat domain would you like to use for the production site? (This value will be used in static/CNAME)"
declare PRODUCTION_DOMAIN=""
while [ -z "$PRODUCTION_DOMAIN" ]; do
    read -p ": " PRODUCTION_DOMAIN
done

# Setting CNAME
echo $PRODUCTION_DOMAIN > ./static/CNAME

# Prompt for GitHub Repo creation
echo -en "\nTime to create your remote repository on GitHub, come back here when you have created it. Don't add any files to the repo."
echo -e "\nopening https://github.com/new\n"
read -p "Press enter to continue ..." any_key
open "https://github.com/new"

declare REPO_NAME_CORRECT="false"
while [ "$REPO_NAME_CORRECT" == "false" ]; do
    echo -e "\nEnter the owner of the repository"
    declare REPO_ORGANISATION=""
    while [ -z "$REPO_ORGANISATION" ]; do
        read -p ": " REPO_ORGANISATION
    done

    echo -e "\nEnter the repository name"
    declare REPO_PROJECT=""
    while [ -z "$REPO_PROJECT" ]; do
        read -p ": " REPO_PROJECT
    done

    echo -e "\nYour new repository is located at 'https://github.com/${REPO_ORGANISATION}/${REPO_PROJECT}'"
    echo "Is this correct? (y/N)"
    read -p ": " IS_CORRECT
    [ "$IS_CORRECT" == "y" ] && REPO_NAME_CORRECT="true" || { REPO_ORGANISATION=""; REPO_PROJECT=""; }
done

# Prompt for linking repo in CircleCI
echo -en "\nCreate the project in CircleCI"
echo -e "\nOpening https://circleci.com/add-projects/gh/${REPO_ORGANISATION}"
read -p "Press enter to continue ..." any_key
open "https://circleci.com/add-projects/gh/$REPO_ORGANISATION"

echo -en "\nHave you created the CircleCI project? (y/N)"
declare CREATED_CIRCLE_CI_PROJECT="false"
while [ "$CREATED_CIRCLE_CI_PROJECT" == "false" ]; do
    read -p ": " created
    [ "$created" == "y" ] && CREATED_CIRCLE_CI_PROJECT="true"
done

# Prompt for adding private deployment key to CircleCI
echo -e "\nAdd deployment keys to CircleCI"
echo -e "\nSet the host to 'github.com'\n"
echo "$PRIVATE_KEY"
echo -e "\n\nOpening https://circleci.com/gh/${REPO_ORGANISATION}/${REPO_PROJECT}/edit#ssh"
read -p "Press enter to continue ..." any_key
open "https://circleci.com/gh/$REPO_ORGANISATION/$REPO_PROJECT/edit#ssh"

echo -e "\nHave you copied the private key above into CircleCI? (y/N)"
declare PRIVATE_KEY_COPIED="false"
while [ "$PRIVATE_KEY_COPIED" == "false" ]; do
    read -p ": " copied
    [ "$copied" == "y" ] && PRIVATE_KEY_COPIED="true"
done

# Prompt for adding environment variables to CircleCI
echo -e "\nSet up CircleCI environment variables. Copy the following:"
echo -en "\n* GIT_EMAIL = $GIT_EMAIL"
echo -en  "\n* GIT_USERNAME = $GIT_USERNAME"
echo -en  "\n* GITHUB_USERNAME = $GITHUB_USERNAME"
echo -en  "\n* GITHUB_TOKEN = $GITHUB_TOKEN"

echo

echo -e "\nOpening https://circleci.com/gh/${REPO_ORGANISATION}/${REPO_PROJECT}/edit#env-vars"
read -p "Press enter to continue ..." any_key
open "https://circleci.com/gh/$REPO_ORGANISATION/$REPO_PROJECT/edit#env-vars"

echo -e "\nHave you copied the environment variables above into CircleCI? (y/N)"
declare ENV_VARS_COPIED="false"
while [ "$ENV_VARS_COPIED" == "false" ]; do
    read -p ": " copied
    [ "$copied" == "y" ] && ENV_VARS_COPIED="true"
done

# Adding fingerprint to Circle CI config
sed "s/<<DEPLOYMENT_SSH_KEY_FINGERPRINT>>/$KEY_FINGERPRINT/g" ./.circleci/sample_config.yml > ./.circleci/config.yml
rm ./.circleci/sample_config.yml

# Remove self script at this point so it does not appear in git history
rm ./scripts/setup.sh

# Remove any references to git and initialise new repo
rm -rf ./.git
git init

# Setting up git and local files
echo -e "\n\nSetting up git origin"
git remote remove origin
git remote add origin "git@github.com:$REPO_ORGANISATION/$REPO_PROJECT.git"

# Adding deployment key to GitHub
curl -u $GITHUB_USERNAME:$GITHUB_TOKEN -d "{\"title\":\"Circle CI writeable key\",\"key\":\"$PUBLIC_KEY\",\"read_only\":false}" -H "Content-Type: application/json" -X POST https://api.github.com/repos/$REPO_ORGANISATION/$REPO_PROJECT/keys

# Pushing code to trigger build
echo -e "\nPushing code to remote repository"
git add --all
git commit -m "Setup site"
git push -u origin master
git checkout -b staging
git push origin staging

# Updating GitHub repo settings via API
echo -e "\nSetting the default branch to staging"
curl -u $GITHUB_USERNAME:$GITHUB_TOKEN -d '{"default_branch":"staging"}' -H "Content-Type: application/json" -X PATCH https://api.github.com/repos/$REPO_ORGANISATION/$REPO_PROJECT

# Link netlify instructions
echo -e "\nLink project to netlify"
echo -en "\n* Set branch to deploy as 'staging'"
echo -en "\n* Set build command to 'npm run build'"
echo -en "\n* Set publish directory to 'public/'"
echo -e "\n\nOpening https://app.netlify.com/"
read -p "Press enter to continue ..." any_key
open "https://app.netlify.com/"

echo -e "\nHave you linked the project with Netlify? (y/N)"
declare NETLIFY_LINKED="false"
while [ "$NETLIFY_LINKED" == "false" ]; do
    read -p ": " copied
    [ "$copied" == "y" ] && NETLIFY_LINKED="true"
done

echo -e "\nOnce Netlify site has been setup, go to the sites settings in Netlify"
echo -en "\n* Navigate to 'identity'"
echo -en "\n* Enable identity"
echo -en "\n* Enable Git Gateway (if this fails then you may need to manually generate the access token https://help.github.com/en/articles/creating-a-personal-access-token-for-the-command-line)"

echo -e "\n\nHave you updated the Netlify site settings? (y/N)"
declare NETLIFY_SETTINGS_UPDATED="false"
while [ "$NETLIFY_SETTINGS_UPDATED" == "false" ]; do
    read -p ": " copied
    [ "$copied" == "y" ] && NETLIFY_SETTINGS_UPDATED="true"
done

echo -e "\n\nThat concludes the setup process.\nSome additional optional steps:"
echo -en "\n* Configure access on GitHub repo"
echo -en "\n* Configure branch protection on GitHub repo"
echo -en "\n* Setup identity and security on Netlify"
echo -en "\n* Setup Google Analytics and insert tracking ID into 'src/config/index.js'"
echo -e "\n* Setup a new project in Uploadcare for static assets\n"

read -p "Press enter to complete setup ..." any_key
