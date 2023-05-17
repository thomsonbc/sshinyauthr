# sshinyauthr

`sshinyauthr` is an R package providing module functions that can be used to add an authentication layer to your shiny apps. It is a fork of `shinyauthr` (by Paul Campbell, [available here](https://github.com/PaulC91/shinyauthr)). `shinyauthr` stores user and hashed password details within a dataframe, whereas `sshinyauthr` has the capability of authorising a login by validating an SSH connection.

SSH connections are validated by first pinging (using [pingr](https://github.com/r-lib/pingr#readme)) the specified host to ensure it exists, then attempting to login using the `ssh` [package](https://cran.r-project.org/web/packages/ssh/vignettes/intro.html) with the user / password supplied. If the login attempt is successful then access to the app is granted for the user and the SSH connection is immediately closed.

This fork was developed to be able to take advantage of existing user groups on remote hosts, bypassing a requirement of specifying an object containing users and hashed passwords in `shinyauthr`. In our specific use-case, users are able to login to a Shiny app using their institutional details. This means they do not have to create new registration details for the app and continue to be bound by the institution's IT policies.

Most of the README below is adapted from the original repository, and will be modified over time to reflect the changes in this package.

## Installation

Install the development version from github with the [remotes package](https://github.com/r-lib/remotes).

``` r
remotes::install_github("thomsonbc/sshinyauthr")
```

## Run example apps

Code for example apps using various UI frameworks can be found in [inst/shiny-examples](inst/shiny-examples). You can launch 3 example apps with the `runExample` function.

``` r
# login with system user/password. Local SSH logins must be enabled.
shinyauthr::runExample("basic")
shinyauthr::runExample("shinydashboard")
shinyauthr::runExample("navbarPage")
```

## Usage

The package provides 2 module functions each with a UI and server element:

-   `loginUI()`
-   `sshLoginServer()`
-   `logoutUI()`
-   `logoutServer()`

**Note**: the server modules use shiny's new (version \>= 1.5.0) `shiny::moduleServer` method as opposed to the `shiny::callModule` method used by the now deprecated `sshinyauthr::login` and `sshinyauthr::logout` functions. These functions will remain in the package for backwards compatibility but it is recommended you migrate to the new server functions. This will require some adjustments to the module server function calling method used in your app. For details on how to migrate see the 'Migrating from callModule to moduleServer' section of [Modularizing Shiny app code](https://shiny.rstudio.com/articles/modules.html).

Below is a minimal reproducible example of how to use the authentication modules in a shiny app. Note that this package invisibly calls `shinyjs::useShinyjs()` internally and there is no need for you to do so yourself (although there is no harm if you do).

``` r
library(shiny)

ui <- fluidPage(
  # add logout button UI
  div(class = "pull-right", sshinyauthr::logoutUI(id = "logout")),
  # add login panel UI function
  shinyauthr::loginUI(id = "login"),
  # setup table output to show user info after login
  tableOutput("user_table"),
  # setup table output to show another table after manager login
  tableOutput("manager_table")
)

server <- function(input, output, session) {
  # call login module supplying host and port
  # set manager_env as 'USER' environment variable and login with standard user details
  # ssh on local machine needs to be enabled 
  credentials <- sshinyauthr::sshLoginServer(
    id = "login",
    log_out = reactive(logout_init()),
    host = '127.0.0.1',
    port = 22,
    manager_env = 'USER',
    sep = ",",
    reload_on_logout = FALSE,
    cookie_logins = FALSE
  )
  
  # call the logout module with reactive trigger to hide/show
  logout_init <- sshinyauthr::logoutServer(
    id = "logout",
    active = reactive(credentials()$user_auth)
  )
  
  output$user_table <- renderTable({
    # use req to only render results when credentials()$user_auth is TRUE
    req(credentials()$user_auth)
    credentials()$info
  })
  
  output$manager_table <- renderTable({
    # use req to only render results when credentials()$manager is TRUE
    req(credentials()$manager)
    data.frame(manager=TRUE)
  })
}

if (interactive()) shinyApp(ui = ui, server = server)
```

## Details

When the login module is called, it returns a reactive list containing 3 elements:

-   `user_auth`
-   `info`
-   `manager`

The initial values of these variables are `FALSE`, `NULL`, and `FALSE` respectively. However, given a data frame or tibble containing user names, passwords and other user data (optional), the login module will assign a `user_auth` value of `TRUE` if the user supplies a matching user name and password. The value of `info` then becomes the row of data associated with that user which can be used in the main app to control content based on user permission variables etc.

The logout button will only show when `user_auth` is `TRUE`. Clicking the button will reset `user_auth` back to `FALSE` which will hide the button and show the login panel again.

You can set the code in your server functions to only run after a successful login through use of the `req()` function inside all reactives, renders and observers. In the example above, using `req(credentials()$user_auth)` inside the `renderTable` function ensures the table showing the returned user information is only rendered when `user_auth` is `TRUE`.

A note on the `manager` element - This is a boolean value used to determine whether a user should have 'manager' privileges or not. To give users these privileges it is necessary to first specify them in an environment variable. By default the `sshLoginServer` function looks for a comma-separated list of users specified under the `MANAGER` environment variable. It is useful to specify an environment file (`.env`) in the app directory and load it with the `dotenv` [package](https://github.com/motdotla/dotenv):

```         
#Navigate to app folder
cd /path/to/app/folder

touch .env
```

Edit the `.env` file to include the following:

```         
MANAGER=user1,user2
```

Within the app file, typically `app.R`, load the `.env` file:

```         
dotenv::load_dot_env()
```

## Cookie-Based Authentication

Most authentication systems use browser cookies to avoid returning users having to re-enter their user name and password every time they return to the app. `shinyauthr` provides a method for cookie-based automatic login, but you must create your own functions to save and load session info into a database with [persistent data storage](https://shiny.rstudio.com/articles/persistent-data-storage.html).

The first required function must accept two parameters `user` and `session`. The first of these is the user name for log in. The second is a randomly generated string that identifies the session. The app asks the user's web browser to save this session id as a cookie.

The second required function is called without parameters and must return a data.frame of valid `user` and `session` ids. If the user's web browser sends your app a cookie which appears in the `session` column, then the corresponding `user` is automatically logged in.

Pass these functions to the login module via `shinyauthr::loginServer(...)` as the `cookie_setter` and `cookie_getter` parameters. A minimal example, using [RSQLite](https://rsqlite.r-dbi.org/) as a local database to write and store user session data, is below.

``` r
library(shiny)
library(dplyr)
library(lubridate)
library(DBI)
library(RSQLite)

# connect to, or setup and connect to local SQLite db
if (file.exists("my_db_file")) {
  db <- dbConnect(SQLite(), "my_db_file")
} else {
  db <- dbConnect(SQLite(), "my_db_file")
  dbCreateTable(db, "sessionids", c(user = "TEXT", sessionid = "TEXT", login_time = "TEXT"))
}

# a user who has not visited the app for this many days
# will be asked to login with user name and password again
cookie_expiry <- 7 # Days until session expires

# This function must accept two parameters: user and sessionid. It will be called whenever the user
# successfully logs in with a password.  This function saves to your database.

add_sessionid_to_db <- function(user, sessionid, conn = db) {
  tibble(user = user, sessionid = sessionid, login_time = as.character(now())) %>%
    dbWriteTable(conn, "sessionids", ., append = TRUE)
}

# This function must return a data.frame with columns user and sessionid  Other columns are also okay
# and will be made available to the app after log in as columns in credentials()$user_auth

get_sessionids_from_db <- function(conn = db, expiry = cookie_expiry) {
  dbReadTable(conn, "sessionids") %>%
    mutate(login_time = ymd_hms(login_time)) %>%
    as_tibble() %>%
    filter(login_time > now() - days(expiry))
}

# dataframe that holds usernames, passwords and other user data
user_base <- tibble::tibble(
  user = c("user1", "user2"),
  password = c("pass1", "pass2"),
  permissions = c("admin", "standard"),
  name = c("User One", "User Two")
)

ui <- fluidPage(
  # add logout button UI
  div(class = "pull-right", shinyauthr::logoutUI(id = "logout")),
  # add login panel UI function
  shinyauthr::loginUI(id = "login", cookie_expiry = cookie_expiry),
  # setup table output to show user info after login
  tableOutput("user_table")
)

server <- function(input, output, session) {

  # call the logout module with reactive trigger to hide/show
  logout_init <- shinyauthr::logoutServer(
    id = "logout",
    active = reactive(credentials()$user_auth)
  )

  # call login module supplying data frame, user and password cols
  # and reactive trigger
  credentials <- shinyauthr::loginServer(
    id = "login",
    data = user_base,
    user_col = user,
    pwd_col = password,
    cookie_logins = TRUE,
    sessionid_col = sessionid,
    cookie_getter = get_sessionids_from_db,
    cookie_setter = add_sessionid_to_db,
    log_out = reactive(logout_init())
  )

  # pulls out the user information returned from login module
  user_data <- reactive({
    credentials()$info
  })

  output$user_table <- renderTable({
    # use req to only render results when credentials()$user_auth is TRUE
    req(credentials()$user_auth)
    user_data() %>%
      mutate(across(starts_with("login_time"), as.character))
  })
}

shinyApp(ui = ui, server = server)
```

## Credits

`sshinyauthr` is a fork of `shinyauthr`, itself originally borrowing some code from treysp's [shiny_password](https://github.com/treysp/shiny_password) template with the goal of making implementation simpler for end users and allowing the login/logout UIs to fit easily into any UI framework, including [shinydashboard](https://rstudio.github.io/shinydashboard/).

Thanks to [Michael Dewar](https://github.com/michael-dewar) for his contribution of cookie-based authentication. Some code was borrowed from calligross's [Shiny Cookie Based Authentication Example](https://gist.github.com/calligross/e779281b500eb93ee9e42e4d72448189) and from an earlier PR from [aqualogy](https://github.com/aqualogy/shinyauthr).

## Disclaimer

I'm not a security professional so cannot guarantee this authentication procedure to be foolproof. It is ultimately the shiny app developer's responsibility not to expose any sensitive content to the client without the necessary login criteria being met.

I would welcome any feedback on any potential vulnerabilities in the process. I know that apps hosted on a server without an SSL certificate could be open to interception of user names and passwords submitted by a user. As such I would not recommend the use of sshinyauthr without a HTTPS connection.

For apps intended for use within commercial organisations, I would recommend one of RStudio's commercial shiny hosting options, or [shinyproxy](https://www.shinyproxy.io/), both of which have built in authentication options.

However, I hope that having an easy-to-implement open-source shiny authentication option like this will prove useful when alternative options are not feasible.

*Paul Campbell* edited by *Bennett Thomson*
