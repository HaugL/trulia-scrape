#! /usr/bin/env ruby
require 'nokogiri'
require 'open-uri'
require 'active_record'
require 'pg'

trulia_url = "http://www.trulia.com/for_rent/Denver,CO/13_zm/39.71027216428102,39.76914423054568,-105.06184446655271,-104.90219938598631_xy"
# "http://www.trulia.com/for_rent/Denver,CO/13_zm/39.71027216428102,39.76914423054568,-105.06184446655271,-104.90219938598631_xy/3_p"
 
ActiveRecord::Base.establish_connection(
  adapter: "postgresql",
  encoding: "unicode",
  database: "re_scraper"
)

class Property < ActiveRecord::Base
  self.table_name = "models"
end

def convertFormattedNumber(val)
  return val.gsub(",", "").to_i
end

def getAddress(propertyPage)
  address = propertyPage.search(".h3.typeReversed.pvs").text
  address.slice! "Communities near "
  return address
end

def getBeds(element)
  if beds = element.match(/\S+ (Bedrooms|Bedroom)/)[0] rescue nil
    return beds.gsub(/(Bedrooms|Bedroom)  /, "").to_i rescue nil
  elsif beds = element.match(/\d bd/)[0] rescue nil
    return beds.gsub(" bd", "").to_i rescue nil
  end
end

def getBaths(element)
  if baths = element.match(/.+ Bathroom/)[0] rescue nil
    return baths.match(/\d+.\d+|(\d+)/)[0].to_f rescue nil
  elsif baths = element.match(/.+ ba/)[0] rescue nil
    return baths.gsub(" ba", "").to_f rescue nil
  end
end

def getPrice(element)
  # puts element
  price = element.match(/(\$.+)/)[0] rescue nil
  if price
    # If range
    if price.include? "-"
      return convertFormattedNumber(price.split("-")[0].gsub("$", ""))
    # If single
    else
      return convertFormattedNumber(price.gsub("$", ""))
    end
  end
end

def getSQFT(element)
  # convertFormattedNumber(detailsElement.match(/(\d+|\d+,\d+) sqft/)[0].gsub(" sqft", "")) rescue nil
  convertFormattedNumber(element.match(/(\d+|\d+,\d+|\d+\s+|\d+,\d+\s+) sqft/)[0].gsub(" sqft", "")) rescue nil
end

def getPropertyDetails(detailsElement)
  details = {}
  details['sqft'] = getSQFT(detailsElement)
  details['price'] = getPrice(detailsElement)
  details['beds'] = getBeds(detailsElement)
  details['baths'] = getBaths(detailsElement)
  return details
end


def scrapeListPage(listPage)
  listPage.search("li.propertyCard").each do |listItem|
    link = listItem.search("a.primaryLink.pdpLink.activeLink")[0]['href']
    puts link
    propertyPage = Nokogiri::HTML(open("http://www.trulia.com" + link))
    detailsContainer = propertyPage.search("#listingHomeDetailsContainer > div.mtl")[0].content
    generalDetails = getPropertyDetails(detailsContainer)
    generalDetails['address'] = getAddress(propertyPage)
    generalDetails['trulia_id'] = link
    generalDetails['neighborhood'] = propertyPage.search(".mediaBody.h7")[0].content.match(/neighborhood \D+\./)[0].gsub("neighborhood ", "").gsub(".", "") rescue nil
    # If there are multiple units
    floorPlans = propertyPage.search("#floorPlans")[0].search("tr") rescue nil
    puts floorPlans.length
    if floorPlans && floorPlans.length > 0
      puts "Floor Plans"
      puts floorPlans.length
      floorPlans.each do |floorPlan|
        details = getPropertyDetails(floorPlan.content)
        details['address'] = generalDetails['address']
        details['trulia_id'] = generalDetails['trulia_id']
        details['neighborhood'] = generalDetails['neighborhood']
        saveValidProperty(details)
      end
    # Otherwise
    else
      puts "No Floor Plans"
      saveValidProperty(generalDetails)
    end
    sleep(5)
  end
end


def saveValidProperty(details)
  if validProperty(details)
    details.delete_if { |k, v| v == nil }
    currentProperties = Property.where(details).select do |property|
      property.last_seen.month == Time.now().month && property.last_seen.year == Time.now().year
    end
    if currentProperties.length == 0
      details['last_seen'] = Time.now()
      Property.new(details).save()
    end
  end
end

def validProperty(details)
  if !details['price']
    puts details['trulia_id'] + " has no price"
    return false
  elsif !details['beds']
    puts details['trulia_id'] + " has no beds"
  end
  return true
end

moDeets = []

firstPage = Nokogiri::HTML(open(trulia_url))
scrapeListPage(firstPage)
pages = firstPage.search(".srpPagination_list > a").last.text.to_i
(2..pages).each do |index|
  puts index
  link = trulia_url.dup + "/"+index.to_s+"_p"
  page = Nokogiri::HTML(open(link))
  scrapeListPage(page)
  sleep(60)
end