

warnings = () ->
    # Check fdr-column
    el = $('#fdr-column').siblings('.text-error')
    el.text('')
    if !mod_settings.analyze_server_side && !mod_settings.fdr_column
        $(el).text('You must specify the False Discovery Rate column')

    # Check avg-column
    el = $('#avg-column').siblings('.text-error')
    el.text('')
    if !mod_settings.analyze_server_side && !mod_settings.avg_column
        $(el).text('You must specify the Average Expression column')

valid_int = (str) ->
    str!='' && parseInt(str).toString() == str

# Return the longest common prefix of the list of strings passed in
common_prefix = (lst) ->
    lst = lst.slice(0).sort()
    tem1 = lst[0]
    s = tem1.length
    tem2 = lst.pop()
    while(s && (tem2.indexOf(tem1) == -1 || "_-".indexOf(tem1[s-1])>=0))
        tem1 = tem1.substring(0, --s)
    tem1


init_page = () ->
    if full_settings?
        if full_settings['extra_menu_html']
            $('#right-navbar-collapse').append(full_settings['extra_menu_html'])


$(document).ready(() -> setup_nav_bar() )
#$(document).ready(() -> init() )
$(document).ready(() -> $('[title]').tooltip())


flds_optional = ["ec_column","link_column","link_url","min_counts","min_cpm","min_cpm_samples",
                 "fdr_column","avg_column"]
from_server_model = (mdl) ->
    res = $.extend(true, {}, mdl)

    # Optional fields, we use empty string to mean missing
    for c in flds_optional
        res[c] ?= ""

    # init_select goes into replicates
    new_reps = []
    for r in res.replicates
        new_reps.push(
            name: r[0]
            cols: r[1]
            init: r[0] in res.init_select
            factor: r[0] in res.hidden_factor
        )
    res.replicates = new_reps

    console.log("server model",mdl,res)
    res

to_server_model = (mdl) ->
    res = $.extend(true, {}, mdl)
    res.info_columns ?= []
    res.fc_columns ?= []
    # Optional fields, we use empty string to mean missing
    for c in flds_optional
        if res[c]==""
            delete res[c]
    res.init_select = []
    res.hidden_factor = []
    new_reps = []
    for r in res.replicates
        new_reps.push([r.name, r.cols])
        if r.init
            res.init_select.push(r.name)
        if r.factor
            res.hidden_factor.push(r.name)
    res.replicates = new_reps

    console.log("my model",mdl,res)
    res


Multiselect = require('vue-multiselect').default

module.exports =
    components: { Multiselect },
    data: ->
        settings:
            info_columns: []
            fc_columns: []
        csv_data: ""
        asRows: []
        orig_settings:
            is_owner: false
        modal:
            msgs: ""
            msgs_class: ""
    computed:
        code: () ->
            get_url_vars()["code"]
        view_url: () ->
            "compare.html?code=#{this.code}"
        can_lock: () ->
            this.orig_settings.is_owner
        grid_watch: () ->
            this.csv_data
            this.columns_info
            Date.now()
        columns_info: () ->
            #console.log "Parsing!"
            asRows = null
            if this.settings.csv_format
                asRows = d3.csv.parseRows(this.csv_data)
            else
                asRows = d3.tsv.parseRows(this.csv_data)
            [column_keys,this.asRows...] = asRows
            column_keys ?= []
            column_keys
    methods:
        save: () ->
            err = this.check_conditon_names()
            if err.length>0
                this.modal.msgs_class = 'alert alert-danger'
                this.modal.msgs = err
                $('#saving-modal').modal({'backdrop': true, 'keyboard' : true})
                $('#saving-modal .view').hide()
                $('#saving-modal .modal-footer').show()
                $('#saving-modal #close-modal').click( () -> $('#saving-modal').modal('hide'))
                return

            $('#saving-modal').modal({'backdrop': 'static', 'keyboard' : false})
            this.modal.msgs_class = 'alert alert-info'
            this.modal.msgs = ["Saving..."]
            $('#saving-modal .modal-footer').hide()

            to_send = to_server_model(this.settings)
            $.ajax(
                type: "POST"
                url: this.script("settings")
                data: {settings: JSON.stringify(to_send)}
                dataType: 'json'
            ).done((x) =>
                this.modal.msgs_class = 'alert alert-success'
                this.modal.msgs = ["Save successful"]
                $('#saving-modal .view').show()
            ).fail((x) =>
                log_error("ERROR",x)
                this.modal.msgs_class = 'alert alert-danger'
                this.modal.msgs = ["Failed : #{x.responseText}"]
                $('#saving-modal .view').hide()
            ).always(() =>
                $('#saving-modal').modal({'backdrop': true, 'keyboard' : true})
                $('#saving-modal .modal-footer').show()
                $('#saving-modal #close-modal').click( () -> window.location = window.location)
            )
        revert: () ->
            this.settings = from_server_model(this.orig_settings.settings)
        check_conditon_names: () ->
            invalid = []
            for rep in this.settings.replicates
                if (rep.name in this.columns_info)
                    invalid.push("ERROR : Cannot use condition name '#{rep.name}', it is already a column name")
                if (rep.name=="")
                    invalid.push("Missing condition name")
            invalid
        add_replicate: () ->
            r = {name:"",cols:[],init:false,factor:false}
            this.settings.replicates.push(r)
            if this.settings.replicates.length<=2
                r.init=true
        del_replicate: (idx) ->
            this.settings.replicates.splice(idx, 1)
        selected_reps: (rep) ->
            n = common_prefix(rep.cols)
            rep.name = n
        script: (typ) ->
            "#{this.code}/#{typ}"
        setup_grid: () ->
            options =
                enableCellNavigation: false
                enableColumnReorder: false
                multiColumnSort: false
                forceFitColumns: true
            this.grid = new Slick.Grid("#grid", [], [], options)

        get_csv_data: () ->
            d3.text(this.script("partial_csv"), "text/csv", (err,dat) =>
                if err
                    $('div.container').text("ERROR : #{err.statusText}")
                    return
                this.csv_data = dat
            )
        get_settings: () ->
            if !this.code?
                log_error("No code defined")
            else
                d3.json(this.script("settings"), (err,json) =>
                    if err
                        log_error "Failed to get settings!",err.statusText
                        return
                    this.orig_settings=json
                    this.revert()
                    if this.orig_settings['extra_menu_html']
                        $('#right-navbar-collapse').append(this.orig_settings['extra_menu_html'])
                )
    watch:
        'settings.name': () -> document.title = this.settings.name
        csv_data: () ->
            # Guess the format, if we haven't set a name yet
            if this.name==""
                this.csv_format = this.csv_data.split("\t").length<10

        grid_watch: () ->
            columns = this.columns_info.map((key,i) ->
                id: key
                name: key
                field: i
                sortable: false
                )
            this.grid.setColumns(columns)
            this.grid.setData(this.asRows)
            this.grid.updateRowCount()
            this.grid.render()

    mounted: ->
        this.setup_grid()
        this.get_settings()
        this.get_csv_data()
