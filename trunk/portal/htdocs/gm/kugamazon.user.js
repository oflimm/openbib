// ==UserScript==
// @name          Anreicherung des KUG in Amazon
// @namespace     http:/kug.ub.uni-koeln.de/gm/
// @description	  Verfügbarkeit im KUG in der Amazon Buchanzeige, basiert auf Skript von from http://www.mundell.org
// @include       http://*.amazon.*/*
// ==/UserScript==

// fixed for Firefox 1.5 and GM 0.6.4

(

function()
{

    var libraryUrlPattern = 'http://kug.ub.uni-koeln.de/portal/lastverteilung?view=kug&fs='
    var libraryName = 'KUG';
    var libraryAvailability = /\<status\>available\<\/status\>/;
    var libraryOtherEditions = /other editions available/;
    var notFound = /ISBN nicht gefunden/;

    var libraryLookup = 
    {
        insertLink: function(isbn, hrefTitle, aLabel, color )
        {
            var div = origTitle.parentNode;
//            var title = origTitle.firstChild.nodeValue;
    	    var title = '';

            var newTitle = document.createElement('b');
            newTitle.setAttribute('class','sans');

            var titleText = document.createTextNode(title);
            newTitle.appendChild(titleText);
        
            var br = document.createElement('br');

            var link = document.createElement('a');
            link.setAttribute ( 'title', hrefTitle );
            link.setAttribute('href', libraryUrlPattern + isbn);
            link.setAttribute('style','font-size:small; font-weight:bold; color:' + color);

            var label = document.createTextNode( aLabel );

            link.appendChild(label);

            div.insertBefore(newTitle, origTitle);
            div.insertBefore(link, origTitle);
            div.insertBefore(br, origTitle);
//            div.removeChild(origTitle);
        },

        doLookup: function ( isbn )
        {
            GM_xmlhttpRequest
            ({
                method:'GET',
                url: 'http://kug5.ub.uni-koeln.de/portal/connector/availabilitysummary/' + isbn,
                onload:function(results)
                {
                    page = results.responseText;
                    //alert(page);
                    if ( notFound.test(page) )
                    {
                        var due = page.match(notFound)[1]
                        libraryLookup.insertLink (
                            origTitle.firstChild.nodeValue,
                            "ISBN nicht gefunden",
                            "ISBN nicht gefunden im " + libraryName + " - Klicken Sie hier f&uuml;r eine Recherche",
                            "red"
                        );
                    }
                    else if ( libraryAvailability.test(page) )
                    {
                        libraryLookup.insertLink (
                            isbn,
                            "mindestens in einem Katalog verfügbar",
                            "Verfügbar im KUG",
                            "green"
                        );
                    }
                    else if ( libraryOtherEditions.test(page) )
                    {
                        libraryLookup.insertLink (
                            isbn,
                            "Andere Ausgaben verfügbar",
                            "Im KUG sind andere Ausgaben dieses Titels verfügbar",
                            "green"
                        );
                    }
                    else
                    {
                        libraryLookup.insertLink (
                            isbn,
                            "ISBN nicht vorhanden",
                            "ISBN konnte nicht im KUG gefunden werden",
                            "orange"
                        );
                    }
                }
            });
        }


    }

    try 
    { var isbn = window.content.location.href.match(/\/(\d{7,9}[\d|X|x])\//)[1]; }
     

    catch (e)
    { return; }
    
    var origTitle = document.evaluate("//span[@id='btAsinTitle']", document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null ).singleNodeValue;

    if ( ! origTitle )
    { return; }

//     alert( isbn );
//     alert( origTitle.firstChild.nodeValue );

    libraryLookup.doLookup(isbn);

    }
)();
