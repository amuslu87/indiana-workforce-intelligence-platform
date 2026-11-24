library(shiny)
library(bslib)
library(DBI)
library(odbc)
library(dplyr)
library(plotly)
library(DT)

fmt <- function(x, digits=0) ifelse(is.na(x), 'Unavailable', formatC(x, format='f', digits=digits, big.mark=','))
month_date <- function(y,m) as.Date(sprintf('%04d-%02d-01',as.integer(y),as.integer(m)))
read_snapshot <- function() {
  con <- dbConnect(odbc(), Driver='ODBC Driver 18 for SQL Server', Server=Sys.getenv('IWI_SQL_SERVER','Matt'), Database='IndianaWorkforceDW', Trusted_Connection='Yes', Encrypt='Yes', TrustServerCertificate='Yes')
  on.exit(dbDisconnect(con), add=TRUE)
  dbExecute(con,'SET TRANSACTION ISOLATION LEVEL SERIALIZABLE')
  dbWithTransaction(con, {
    a <- dbGetQuery(con,'SELECT * FROM serving.vw_Unemployment')
    b <- dbGetQuery(con,'SELECT * FROM serving.vw_LaborMarket')
    w <- dbGetQuery(con,'SELECT * FROM serving.vw_OccupationalWages')
    p <- dbGetQuery(con,'SELECT * FROM serving.vw_OccupationalProjection')
    stopifnot(all(c(nrow(a),nrow(b),nrow(w),nrow(p))>0))
    a <- a |> filter(PeriodType=='Monthly') |> mutate(Date=month_date(ReportingYear,MonthCode))
    b$Date <- as.Date(b$ReportingDate)
    p <- p |> mutate(NetChange=ProjectedEmployment-BaseEmployment, GrowthPct=ifelse(BaseEmployment>0,100*NetChange/BaseEmployment,NA_real_))
    list(a=a,b=b,w=w,p=p,counts=c(nrow(a),nrow(b),nrow(w),nrow(p)),loaded=Sys.time())
  })
}
chart <- function(p,y='') layout(p,paper_bgcolor='#151c29',plot_bgcolor='#151c29',font=list(color='#edf2fa'),xaxis=list(gridcolor='#303a49'),yaxis=list(title=y,gridcolor='#303a49'),margin=list(l=75,r=20,t=25,b=65))
trend <- function(d,y,label) {
  validate(need(nrow(d)>0,'No observations for this selection'))
  dates <- data.frame(Date=seq(min(d$Date),max(d$Date),by='month'))
  d <- merge(dates,d[,c('Date',y)],by='Date',all.x=TRUE)
  chart(plot_ly(d,x=~Date,y=d[[y]],type='scatter',mode='lines+markers',connectgaps=FALSE,line=list(color='#38d9ff'),marker=list(size=5)),label)
}
rank_chart <- function(d,col,label) {
  d <- d[!is.na(d[[col]]),,drop=FALSE]; d <- head(d[order(d[[col]],decreasing=TRUE),],15)
  validate(need(nrow(d)>0,'No available estimates'))
  chart(plot_ly(d,x=d[[col]],y=~OccupationTitle,type='bar',orientation='h',marker=list(color='#f4d64e')) |> layout(yaxis=list(categoryorder='total ascending',automargin=TRUE),xaxis=list(title=label)))
}
ui <- page_navbar(title='INDIANA | Workforce Intelligence',fillable=FALSE,theme=bs_theme(version=5,bg='#0d111a',fg='#edf2fa',primary='#38d9ff'),
  header=tagList(tags$style(HTML('.card{background:#151c29;border:1px solid #303a49;} .navbar{border-bottom:1px solid #303a49;} .metric{font-size:2rem;font-weight:700;color:#38d9ff;} .dataTables_wrapper{color:#edf2fa;} .compact-filters .shiny-input-container{margin-bottom:0;width:100%;} .compact-filters p{margin:0;} .btn-default,.btn-outline-secondary,.shiny-download-link{color:#38d9ff!important;border-color:#38d9ff!important;} .dataTables_scrollHead{background:#151c29;}')),div(class='p-3',actionButton('refresh','Refresh data'),textOutput('status'))),
  nav_panel('Overview',layout_columns(card(card_header('State unemployment'),uiOutput('rate')),card(card_header('Projected employment growth'),uiOutput('growth')),card(card_header('County coverage'),uiOutput('coverage')),col_widths=c(4,4,4)),card(card_header('State unemployment trend'),plotlyOutput('stateTrend')),card(card_header('Published dataset inventory'),DTOutput('inventory'))),
  nav_panel('Regional',layout_columns(card(selectInput('geo','Geography',choices=NULL),selectInput('period','County comparison month',choices=NULL)),card(card_header('Monthly unemployment'),plotlyOutput('regionalTrend')),col_widths=c(3,9)),card(card_header('County comparison — same reporting month'),DTOutput('counties'))),
  nav_panel('Labor market',card(selectInput('measure','Measure',choices=c('UNEMPLOYMENT_RATE','EMPLOYED_PERSONS','UNEMPLOYED_PERSONS','CIVILIAN_LABOR_FORCE')),plotlyOutput('laborTrend')),card(DTOutput('laborTable'))),
  nav_panel('Wages',
    card(class='compact-filters', layout_columns(selectInput('wyear','Reference year',choices=NULL),selectInput('wgroup','Occupational level',choices=NULL),downloadButton('wcsv','Export selected data'),col_widths=c(4,4,4))),
    conditionalPanel("input.wgroup && input.wgroup !== 'All levels' && input.wgroup !== 'Unclassified'", card(full_screen=TRUE,card_header('Median annual wage rankings'),plotlyOutput('wageRank',height='320px',fill=FALSE))),
    card(full_screen=TRUE,card_header('Occupational wage estimates'),DTOutput('wages',fill=FALSE))),
  nav_panel('Projections',
    card(class='compact-filters',layout_columns(selectInput('pyear','Projection year',choices=NULL),selectInput('pgroup','Occupational level',choices=NULL),selectInput('rank','Rank by',choices=c('Net employment change'='NetChange','Percentage growth'='GrowthPct')),downloadButton('pcsv','Export selected data'),col_widths=c(3,3,3,3)),p('Net employment change is not annual openings or current vacancies. Base year is unavailable where missing.')),
    conditionalPanel("input.pgroup && input.pgroup !== 'All levels' && input.pgroup !== 'Unclassified'",card(full_screen=TRUE,card_header('Projected employment rankings'),plotlyOutput('projRank',height='320px',fill=FALSE))),
    card(full_screen=TRUE,card_header('Occupational employment projections'),DTOutput('projections',fill=FALSE)))
)
server <- function(input,output,session) {
  cache <- reactiveVal(NULL); status <- reactiveVal('Loading published data...')
  observe({ invalidateLater(300000,session); input$refresh
    tryCatch({x <- read_snapshot(); cache(x); status(paste('Last successful read:',format(x$loaded),'| Published serving views'))},error=function(e){status('Refresh failed. Previous successful data retained if available.'); message(conditionMessage(e))})
  })
  data <- reactive({req(cache()); cache()})
  observeEvent(cache(),{
    x <- data(); a <- x$a; w <- x$w; p <- x$p
    updateSelectInput(session,'geo',choices=sort(unique(a$GeographyName)),selected=if(length(isolate(input$geo)) && isolate(input$geo) %in% a$GeographyName) isolate(input$geo) else a$GeographyName[which(trimws(a$FIPSCode)=='18000')[1]])
    months <- sort(unique(a$Date[trimws(a$FIPSCode)!='18000']),decreasing=TRUE)
    updateSelectInput(session,'period',choices=as.character(months),selected=if(length(isolate(input$period)) && isolate(input$period) %in% as.character(months)) isolate(input$period) else as.character(months[1]))
    for (id in c('wyear','pyear','wgroup','pgroup')) {
      v <- switch(id,wyear=sort(unique(w$ReferenceYear),decreasing=TRUE),pyear=sort(unique(p$ProjectionYear),decreasing=TRUE),wgroup=c('All levels',sort(unique(na.omit(w$OccupationGroup))),'Unclassified'),pgroup=c('All levels',sort(unique(na.omit(p$OccupationGroup))),'Unclassified'))
      old <- isolate(input[[id]]); sel <- if(length(old)&&old %in% v) old else if(id=='wgroup'&&'detailed' %in% v) 'detailed' else v[1]
      updateSelectInput(session,id,choices=v,selected=sel)
    }
  })
  output$status <- renderText(status())
  state <- reactive(data()$a |> filter(trimws(FIPSCode)=='18000') |> arrange(desc(Date)))
  output$rate <- renderUI({d <- state(); req(nrow(d)); tagList(div(class='metric',paste0(fmt(d$UnemploymentRate[1],1),'%')),p(format(d$Date[1],'%B %Y')))})
  output$growth <- renderUI({d <- data()$p |> filter(OccupationCode=='00-0000') |> arrange(desc(ProjectionYear)); validate(need(nrow(d)>0,'Total unavailable')); tagList(div(class='metric',paste0(fmt(d$GrowthPct[1],1),'%')),p(paste('Through',d$ProjectionYear[1])))})
  output$coverage <- renderUI(div(class='metric',length(unique(data()$a$FIPSCode[trimws(data()$a$FIPSCode)!='18000']))))
  output$stateTrend <- renderPlotly(trend(state(),'UnemploymentRate','Percent'))
  output$inventory <- renderDT(datatable(data.frame(Dataset=c('Unemployment (monthly only)','Labor market','Wages','Projections'),Rows=data()$counts),rownames=FALSE,options=list(dom='t')))
  output$regionalTrend <- renderPlotly(trend(filter(data()$a,GeographyName==input$geo),'UnemploymentRate','Percent'))
  output$counties <- renderDT({req(input$period); datatable(data()$a |> filter(trimws(FIPSCode)!='18000',Date==as.Date(input$period)) |> select(GeographyName,Date,UnemploymentRate) |> arrange(desc(UnemploymentRate)),rownames=FALSE)})
  labor <- reactive({req(input$measure); filter(data()$b,MeasureCode==input$measure)})
  output$laborTrend <- renderPlotly({d <- labor(); trend(d,'MeasureValue',paste(unique(d$MeasureUnit),collapse=', '))})
  output$laborTable <- renderDT(datatable(labor() |> select(Date,MeasureCode,MeasureUnit,MeasureValue),rownames=FALSE))
  group_filter <- function(d,g) {if(g=='All levels') d else if(g=='Unclassified') filter(d,is.na(OccupationGroup)) else filter(d,OccupationGroup==g)}
  wages <- reactive({req(input$wyear,input$wgroup); group_filter(filter(data()$w,ReferenceYear==as.integer(input$wyear)),input$wgroup) |> select(-RunID,-FactKey)})
  projections <- reactive({req(input$pyear,input$pgroup); group_filter(filter(data()$p,ProjectionYear==as.integer(input$pyear)),input$pgroup) |> select(-RunID,-FactKey)})
  output$wageRank <- renderPlotly({validate(need(input$wgroup!='All levels','Select one occupational level for comparable rankings.')); rank_chart(wages(),'MedianAnnualWage','Median annual wage (USD)')})
  output$projRank <- renderPlotly({validate(need(!input$pgroup %in% c('All levels','Unclassified'),'Select a classified occupational level for rankings. Unclassified records remain available in the table.')); rank_chart(projections(),input$rank,input$rank)})
  output$wages <- renderDT(datatable(wages(),rownames=FALSE,options=list(scrollX=TRUE,scrollY="55vh",scrollCollapse=FALSE,pageLength=50,lengthMenu=c(25,50,100),autoWidth=TRUE)))
  output$projections <- renderDT(datatable(projections(),rownames=FALSE,options=list(scrollX=TRUE,scrollY="55vh",scrollCollapse=FALSE,pageLength=50,lengthMenu=c(25,50,100),autoWidth=TRUE)))
  output$wcsv <- downloadHandler(filename=function() 'occupational_wages.csv',content=function(file) write.csv(wages(),file,row.names=FALSE,na=''))
  output$pcsv <- downloadHandler(filename=function() 'occupational_projections.csv',content=function(file) write.csv(projections(),file,row.names=FALSE,na=''))
}
shinyApp(ui,server)
