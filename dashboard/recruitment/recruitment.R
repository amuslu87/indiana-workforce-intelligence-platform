recruitment_ui <- function(id) {
  ns <- NS(id)

  tagList(
    p("Source: Work for Indiana | Daily observed job postings"),
    textOutput(ns("status")),

    layout_columns(
      card(card_header("Active postings"),
           uiOutput(ns("active"))),
      card(card_header("Newly observed"),
           uiOutput(ns("new"))),
      card(card_header("No longer observed"),
           uiOutput(ns("removed"))),
      card(card_header("Reactivated"),
           uiOutput(ns("reactivated"))),
      card(card_header("Historical unique postings"),
           uiOutput(ns("total"))),
      col_widths=c(3,2,2,2,3)
    ),

    card(
      card_header("Daily recruitment activity"),
      plotlyOutput(ns("daily"), height="320px"),
      p("Baseline counts represent initial inventory, not new job advertisements.")
    ),

    layout_columns(
      card(full_screen=TRUE,
           card_header("Top recruiting agencies"),
           plotlyOutput(ns("agencies"), height="420px")),
      card(full_screen=TRUE,
           card_header("Top recruiting cities"),
           plotlyOutput(ns("cities"), height="420px")),
      col_widths=c(6,6)
    ),

    card(
      card_header("Detected skills and competencies"),
      plotlyOutput(ns("skills"), height="350px"),
      p("Keyword-based indicators; not verified mandatory requirements.")
    ),

    card(
      card_header("Search and explore job postings"),
      layout_columns(
        selectInput(ns("agency"), "Agency", choices=NULL),
        selectInput(ns("city"), "City", choices=NULL),
        selectInput(ns("active_filter"), "Posting status",
          choices=c("Active","Historical","All")),
        col_widths=c(4,4,4)
      ),
      DTOutput(ns("jobs"),fill=FALSE)
    ),

    card(
      card_header("Compensation intelligence"),
      textOutput(ns("comp_status")),
      p("Description-first base salary with listing fallback."),
      p("Hourly annualization uses 1,950 hours as a full-time-equivalent estimate, not guaranteed annual earnings."),
      DTOutput(ns("compensation"),fill=FALSE)
    ),

    card(
      card_header("Collection quality and completeness"),
      DTOutput(ns("quality"),fill=FALSE)
    )
  )
}

read_recruitment <- function() {
  con <- dbConnect(
    odbc(),
    Driver="ODBC Driver 18 for SQL Server",
    Server=Sys.getenv("IWI_SQL_SERVER","Matt"),
    Database="IndianaWorkforceDW",
    Trusted_Connection="Yes",
    Encrypt="Yes",
    TrustServerCertificate="Yes"
  )

  on.exit(dbDisconnect(con), add=TRUE)

  dbExecute(con,"SET TRANSACTION ISOLATION LEVEL SERIALIZABLE")

  dbWithTransaction(con, {
    views <- c(
      jobs="vw_StateRecruitment",
      daily="vw_RecruitmentDaily",
      agency="vw_RecruitmentAgency",
      location="vw_RecruitmentLocation",
      compensation="vw_RecruitmentCompensation",
      skills="vw_RecruitmentSkills",
      quality="vw_RecruitmentQuality"
    )

    x <- lapply(views,function(v)
      dbGetQuery(con,paste0("SELECT * FROM serving.",v))
    )

    x$daily$ObservationDate <- as.Date(x$daily$ObservationDate)
    x$daily <- x$daily[order(x$daily$ObservationDate),]

    x$jobs$AgencyName <- ifelse(
      is.na(x$jobs$AgencyName) | x$jobs$AgencyName=="",
      x$jobs$AgencyRaw,x$jobs$AgencyName
    )

    x$jobs$AgencyName[
      is.na(x$jobs$AgencyName) | x$jobs$AgencyName==""
    ] <- "Unknown"

    x$jobs$City[
      is.na(x$jobs$City) | x$jobs$City==""
    ] <- "Unknown"

    stopifnot(nrow(x$daily)>0)

    stopifnot(
      sum(as.logical(x$jobs$ObservedActive)) ==
        as.numeric(tail(x$daily$AdvertisedPostings,1))
    )

    stopifnot(
      !anyDuplicated(x$compensation$JobPostingID),
      nrow(x$compensation) ==
        sum(as.logical(x$jobs$ObservedActive))
    )

    x$loaded <- Sys.time()
    x
  })
}

recruitment_server <- function(id, refresh) {
  moduleServer(id,function(input,output,session) {

    cache <- reactiveVal(NULL)
    status <- reactiveVal("Loading recruitment data...")

    observe({
      invalidateLater(300000,session)
      refresh()

      tryCatch({
        x <- read_recruitment()
        cache(x)
        status(paste(
          "Last refreshed:",
          format(x$loaded,"%Y-%m-%d %I:%M %p"),
          "| Latest observation:",
          max(x$daily$ObservationDate)
        ))
      },error=function(e) {
        status("Refresh failed. Previous successful data retained if available.")
        message(conditionMessage(e))
      })
    })

    output$status <- renderText(status())

    data <- reactive({
      req(cache())
      cache()
    })

    latest <- reactive(tail(data()$daily,1))

    metric <- function(value) {
      div(class="metric",fmt(as.numeric(value)))
    }

    output$active <- renderUI(metric(latest()$AdvertisedPostings))
    output$new <- renderUI(metric(latest()$NewlyObservedPostings))
    output$removed <- renderUI(metric(latest()$NoLongerObservedPostings))
    output$reactivated <- renderUI(metric(latest()$ReactivatedPostings))
    output$total <- renderUI(metric(latest()$CumulativeUniquePostings))

    output$daily <- renderPlotly({
      d <- data()$daily

      p <- plot_ly(d,x=~ObservationDate) |>
        add_lines(y=~AdvertisedPostings,
          name="Active",mode="lines+markers",
          line=list(color="#38d9ff")) |>
        add_lines(
          y=ifelse(as.logical(d$IsBaseline),NA,
                   d$NewlyObservedPostings),
          name="Newly observed",mode="lines+markers",
          line=list(color="#f4d64e")) |>
        add_lines(y=~NoLongerObservedPostings,
          name="No longer observed",mode="lines+markers",
          line=list(color="#e879f9"))

      chart(p,"Postings") |> layout(
        xaxis=list(
          title="Observation date",
          type="date",
          tickformat="%b %d, %Y",
          dtick=86400000
        ),
        legend=list(orientation="h",x=0,y=1.12)
      )
    })

    bars <- function(d,label) {
      d$ObservedPostings <- as.numeric(d$ObservedPostings)
      d <- head(d[order(d$ObservedPostings,decreasing=TRUE),],15)

      validate(need(nrow(d)>0,"No available observations"))

      chart(
        plot_ly(d,x=~ObservedPostings,y=d[[label]],
          type="bar",orientation="h",
          marker=list(color="#38d9ff")),""
      ) |> layout(
        yaxis=list(categoryorder="total ascending",
                   automargin=TRUE),
        xaxis=list(title="Observed postings")
      )
    }

    output$agencies <- renderPlotly(
      bars(data()$agency,"AgencyName")
    )

    output$cities <- renderPlotly({
      d <- data()$location
      d$City[is.na(d$City) | d$City==""] <- "Unknown"
      d <- d |>
        group_by(City) |>
        summarise(
          ObservedPostings=sum(as.numeric(ObservedPostings)),
          .groups="drop"
        )

      bars(d,"City")
    })

    output$skills <- renderPlotly({
      d <- data()$skills
      d$SkillLabel <- ifelse(
        d$RequirementType=="UNSPECIFIED",
        d$SkillName,
        paste(d$SkillName,d$RequirementType,sep=" - ")
      )
      bars(d,"SkillLabel")
    })

    observeEvent(cache(),{
      d <- data()$jobs

      for (id in c("agency","city")) {
        col <- if(id=="agency") "AgencyName" else "City"
        choices <- c("All",sort(unique(d[[col]])))
        old <- isolate(input[[id]])
        selected <- if(length(old) && old %in% choices) old else "All"

        updateSelectInput(session,id,
          choices=choices,selected=selected)
      }
    })

    output$jobs <- renderDT({
      req(input$agency,input$city,input$active_filter)

      d <- data()$jobs

      if(input$agency!="All")
        d <- d[d$AgencyName==input$agency,]

      if(input$city!="All")
        d <- d[d$City==input$city,]

      if(input$active_filter=="Active")
        d <- d[as.logical(d$ObservedActive),]

      if(input$active_filter=="Historical")
        d <- d[!as.logical(d$ObservedActive),]

      comp <- data()$compensation

      idx <- match(d$JobPostingID,comp$JobPostingID)

      d$BaseSalary <- comp$SalaryAmount[idx]
      d$SalaryFrequency <- comp$SalaryFrequency[idx]
      d$AnnualizedSalary <- comp$AnnualizedSalary[idx]

      d <- d[,c(
        "JobTitle","AgencyName","City","ZIPCode",
        "MinimumSalaryRaw","BaseSalary","SalaryFrequency",
        "AnnualizedSalary","DatePosted","ObservedActive",
        "ObservationDate","DetailStatus","JobURL"
      )]

      urls <- as.character(d$JobURL)

      safe <- !is.na(urls) &
        grepl("^https://workforindiana[.]in[.]gov/job/[^[:space:]]+$",
              urls)

      d$JobURL <- rep("Unavailable",length(urls))

      d$JobURL[safe] <- paste0(
        '<a href="',
        htmltools::htmlEscape(urls[safe],attribute=TRUE),
        '" target="_blank" rel="noopener noreferrer">',
        'View posting</a>'
      )

      datatable(d,rownames=FALSE,
        escape=setdiff(names(d),"JobURL"),
        filter="top",
        options=list(
          scrollX=TRUE,
          pageLength=25,
          lengthMenu=c(25,50,100)
        ))
    })

    output$comp_status <- renderText({
      d <- data()$compensation

      total <- nrow(d)
      available <- sum(!is.na(d$SalaryAmount))
      explicit <- sum(d$FrequencyBasis=="EXPLICIT",na.rm=TRUE)
      assumed <- sum(d$FrequencyBasis=="SOURCE_ASSUMPTION",na.rm=TRUE)
      unresolved <- total-available

      coverage <- if(total>0) 100*available/total else 0

      paste0(
        "Salary coverage: ",sprintf("%.2f",coverage),"%",
        " | Available: ",available," / ",total,
        " | Explicit frequency: ",explicit,
        " | Assumed frequency: ",assumed,
        " | Unresolved: ",unresolved
      )
    })

    output$compensation <- renderDT({
      d <- data()$compensation |>
        select(
          JobTitle,MinimumSalaryRaw,SalaryAmount,
          SalaryFrequency,AnnualizedSalary,
          FrequencyBasis,StandardizationMethod,
          SalaryValidationStatus
        )

      datatable(
        d,rownames=FALSE,escape=TRUE,
        filter="top",
        colnames=c(
          "Job title","Listing salary","Base salary",
          "Frequency","Annualized salary",
          "Frequency basis","Extraction method",
          "Validation status"
        ),
        options=list(
          scrollX=TRUE,
          pageLength=15,
          lengthMenu=c(15,25,50,100)
        )
      ) |>
        formatCurrency(
          c("SalaryAmount","AnnualizedSalary"),
          currency="$",digits=2
        ) |>
        formatStyle(
          "FrequencyBasis",
          color=styleEqual(
            c("EXPLICIT","SOURCE_ASSUMPTION","UNRESOLVED"),
            c("#38d9ff","#f4d64e","#e879f9")
          )
        )
    })

    output$quality <- renderDT({
      d <- data()$quality |>
        arrange(desc(CollectionDate))

      datatable(d,rownames=FALSE,escape=TRUE,
        options=list(scrollX=TRUE,pageLength=10))
    })
  })
}
