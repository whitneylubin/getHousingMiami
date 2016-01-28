############################################################################################
####################################### SERVICE ############################################
############################################################################################

ListingService = ($http, $localStorage) ->
  Service = {}
  Service.listing = {}
  Service.listings = []
  Service.openListings = []
  Service.closedListings = []
  Service.lotteryResultsListings = []
  # these get loaded after the listing is loaded
  Service.AMI = []
  Service.maxIncomeLevels = []

  $localStorage.favorites ?= []
  Service.favorites = $localStorage.favorites

  Service.eligibility_filter_defaults =
    'household_size': ''
    'income_timeframe': ''
    'income_total': ''
    'include_children_under_6': false
    'children_under_6': ''

  $localStorage.eligibility_filters ?= angular.copy(Service.eligibility_filter_defaults)
  Service.eligibility_filters = $localStorage.eligibility_filters

  Service.getFavoriteListings = () ->
    Service.getListingsByIds(Service.favorites)

  Service.toggleFavoriteListing = (listing_id) ->
    # toggle the value for listing_id
    index = Service.favorites.indexOf(listing_id)
    if index == -1
      # add the favorite
      Service.favorites.push(listing_id)
    else
      # remove the favorite
      Service.favorites.splice(index, 1)

  Service.isFavorited = (listing_id) ->
    Service.favorites.indexOf(listing_id) > -1

  Service.setEligibilityFilters = (filters) ->
    angular.copy(filters, Service.eligibility_filters)

  Service.hasEligibilityFilters = ->
    ! angular.equals(Service.eligibility_filter_defaults, Service.eligibility_filters)

  Service.eligibilityYearlyIncome = ->
    if Service.eligibility_filters.income_timeframe == 'per_month'
      parseFloat(Service.eligibility_filters.income_total) * 12
    else
      parseFloat(Service.eligibility_filters.income_total)

  Service.eligibilityIncomeTimeframe = ->
    # just return 'month' or 'year' and get rid of the 'per_'
    if Service.eligibility_filters.income_timeframe
      Service.eligibility_filters.income_timeframe.split('per_')[1]
    else
      ''

  Service.eligibilityIncomeTotal = ->
    parseFloat(Service.eligibility_filters.income_total)


  Service.eligibilityHouseholdSize = ->
    Service.eligibility_filters.household_size

  # TODO: would be ideal to replace this with a reliable value from Salesforce rather than computing here
  Service.occupancyForUnitType = (unit_type) ->
    if unit_type == 'Studio'
      min = 1
      max = 2
    else
      # pull out the # of rooms e.g. 1 from "1 Bedroom"
      rooms = parseInt(unit_type.substr(0,1))
      min = rooms
      max = (rooms * 2) + 1
    return [min, max]

  # TODO: would be ideal to replace this with a reliable value from Salesforce rather than computing here
  Service.occupancyMinMax = (listing) ->
    minMax = []
    if listing.Units
      listing.Units.forEach (unit) ->
        unitMinMax = Service.occupancyForUnitType(unit.Unit_Type)
        if minMax.length == 0
          # initialize by using the first unit's values
          minMax = unitMinMax
        else
          minMax = [Math.min(minMax[0], unitMinMax[0]), Math.max(minMax[1], unitMinMax[1])]
    return minMax

  Service.maxIncomeLevelsFor = (listing) ->
    # TODO: this should come from the listing object itself (from SF), not our function
    occupancyMinMax = Service.occupancyMinMax(listing)
    incomeLevels = []
    Service.AMI.forEach (amiLevel) ->
      occupancy = parseInt(amiLevel.numOfHousehold)
      # only grab the incomeLevels that fit within our listing's occupancyMinMax
      if occupancy >= occupancyMinMax[0] && occupancy <= occupancyMinMax[1]
        incomeLevels.push({
          occupancy: occupancy,
          yearly: parseFloat(amiLevel.amount),
          monthly: parseFloat(amiLevel.amount) / 12.0
        })
    return incomeLevels

  ###################################### Salesforce API Calls ###################################

  Service.getListing = (_id) ->
    angular.copy({}, Service.listing)
    $http.get("/api/v1/listings/#{_id}.json").success((data, status, headers, config) ->
      angular.copy((if data and data.listing then data.listing else {}), Service.listing)
    ).error( (data, status, headers, config) ->
      # console.log data
    )

  Service.getListings = () ->
    angular.copy([], Service.openListings)
    angular.copy([], Service.closedListings)
    angular.copy([], Service.lotteryResultsListings)
    # check for default state
    if Service.hasEligibilityFilters()
      return Service.getListingsWithEligibility()
    $http.get("/api/v1/listings.json").success((data, status, headers, config) ->
      listings = if data and data.listings then data.listings else []
      Service.groupListings(listings)
    ).error( (data, status, headers, config) ->
      # console.log data
    )

  Service.getListingsWithEligibility = ->
    params =
      eligibility:
        householdsize: Service.eligibility_filters.household_size
        incomelevel: Service.eligibilityYearlyIncome()
        includeChildrenUnder6: Service.eligibility_filters.include_children_under_6
        childrenUnder6: Service.eligibility_filters.children_under_6
    $http.post("/api/v1/listings-eligibility.json", params).success((data, status, headers, config) ->
      listings = (if data and data.listings then data.listings else [])
      Service.groupListings(listings)
    ).error( (data, status, headers, config) ->
      # console.log data
    )

  Service.groupListings = (listings) ->
    now = new Date()
    today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
    listings.forEach (listing) ->
      due_date = new Date(listing.Application_Due_Date)
      if due_date > today
        Service.openListings.push(listing)
      else if due_date < today
        # TODO: check if this is the right field once we're getting it from Salesforce in
        # the /listings endpoint
        if listing.Lottery_Members
          Service.lotteryResultsListings.push(listing)
        else
          Service.closedListings.push(listing)


  # retrieves only the listings specified by the passed in array of ids
  Service.getListingsByIds = (ids) ->
    angular.copy([], Service.listings)
    params = {params: {ids: ids.join(',') }}
    $http.get("/api/v1/listings.json", params).success((data, status, headers, config) ->
      listings = if data and data.listings then data.listings else []
      angular.copy(listings, Service.listings)
    ).error( (data, status, headers, config) ->
      # console.log data
    )

  Service.getListingAMI = ->
    angular.copy([], Service.AMI)
    percent = if (Service.listing && Service.listing.AMI_Percentage) then Service.listing.AMI_Percentage else 100
    $http.get("/api/v1/ami.json?percent=#{percent}").success((data, status, headers, config) ->
      if data && data.ami
        angular.copy(data.ami, Service.AMI)
        angular.copy(Service.maxIncomeLevelsFor(Service.listing), Service.maxIncomeLevels)
    ).error( (data, status, headers, config) ->
      # console.log data
    )


  return Service


############################################################################################
######################################## CONFIG ############################################
############################################################################################

ListingService.$inject = ['$http', '$localStorage']

angular
  .module('dahlia.services')
  .service('ListingService', ListingService)
