// ==UserScript==
// @name          Amazon mit KUG-Verfügbarkeit
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

    var libraryLookup = 
    {
        insertLink: function(isbn, hrefTitle, aLabel, color )
        {
            var div = origTitle.parentNode;
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
        },

       insertSimilar: function(isbn, aSimilarTitles, aLabel, color )
        {                     
            var div = origTitle.parentNode;
    	    var title = '';

            var newTitle = document.createElement('b');
            newTitle.setAttribute('class','sans');

            var titleText = document.createTextNode(title);
            newTitle.appendChild(titleText);
        
            var br = document.createElement('br');

            var span1 = document.createElement('span');
            span1.setAttribute('style','font-size:small; font-weight:bold; color:' + color);
            
            var label = document.createTextNode( aLabel );

            span1.appendChild(label);

            var span2 = document.createElement('span');
            span2.setAttribute('style','font-size:small; font-weight:bold; color:' + color);

            var urlstring = " ( ";
            for (var i=0; i<aSimilarTitles.snapshotLength; i++) {
                var permalink = aSimilarTitles.snapshotItem(i).firstChild.nodeValue;
                urlstring = urlstring+"<a href=\""+permalink+"\" target=\"_blank\">"+(i+1)+"</a> ";
            }
            urlstring = urlstring + ")";
            span2.innerHTML = urlstring;
            
            div.insertBefore(newTitle, origTitle);
            div.insertBefore(span1, origTitle);
            div.insertBefore(span2, origTitle);
            div.insertBefore(br, origTitle);
        },

        doLookup: function ( isbn )
        {
            GM_xmlhttpRequest
            ({
                method:'GET',
                url: 'http://kug.ub.uni-koeln.de/portal/connector/availability/' + isbn,
                onload:function(results)
                {
                    page = results.responseText;
                    var pagexml = (new DOMParser()).parseFromString(page, "text/xml");

                    var availability = pagexml.evaluate("//availability/size", pagexml, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null ).singleNodeValue.firstChild.nodeValue;
                    //GM_log('Availability:'+availability);

                    var similar_availability = pagexml.evaluate("//similar_record_availability/size", pagexml, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null ).singleNodeValue.firstChild.nodeValue;
                    //GM_log('Similar Availability:'+similar_availability);

                    //alert(page);
                    if ( availability > 0 )
                    {
                        libraryLookup.insertLink (
                            isbn,
                            "in mindestens einem Katalog vorhanden",
                            availability+" Titel im KUG vorhanden",
                            "green"
                        );
                    }
                    else if ( similar_availability > 0 )
                    {
                        var similar_titles = pagexml.evaluate("//similar_record_availability/catalogue/permalink", pagexml, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null );

                        libraryLookup.insertSimilar (
                            isbn,
                            similar_titles,
                            similar_availability+" Titel im KUG in anderen Ausgaben vorhanden ",
                            "orange"
                        );
                    }
                    else
                    {
                        libraryLookup.insertLink (
                            isbn,
                            "nicht im KUG vorhanden",
                            "Titel nicht im KUG vorhanden",
                            "red"
                        );
                    }
                }
            });
        }


    }

    //GM_log('running on GBS Skript');

    try { 
      var isbn = window.content.location.href.match(/\/(\d{7,9}[\d|X|x])\//)[1];
    }
    catch (e) { 
       //GM_log('Fehler im isbn try');
       return; 
    }

    var origTitle = document.evaluate("//span[@id='btAsinTitle']", document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null ).singleNodeValue;

//    GM_log('Titel:'+origTitle.firstChild.nodeValue );
    if ( ! origTitle )
    { return; }

//     GM_log('ISBN:'+ isbn );

    libraryLookup.doLookup(isbn);

    }
)();
