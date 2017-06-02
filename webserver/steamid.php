<?php

// https://github.com/mukunda-/steamidparser/blob/master/lib/steamid.php
/*!
 * SteamID Parser
 *
 * Copyright 2014 Mukunda Johnson
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

/**
 * Exception thrown on resolution failure
 * (only used when resolving vanity URLs.).
 */
class SteamIDResolutionException extends Exception
{
    const UNKNOWN = 0;            // Unknown error.
    const CURL_FAILURE = 1;       // cURL/network related error.
    const VANITYURL_NOTFOUND = 2; // The vanity URL given was invalid.
    const VANITYURL_FAILED = 3;   // Steam failure when trying to resolve vanity URL.

    public $reason;

    public function __construct($reason, $text)
    {
        $this->reason = $reason;
        parent::__construct($text);
    }
}

/** ---------------------------------------------------------------------------
 * SteamID.
 *
 * Contains a User Steam ID.
 *
 * @author Mukunda Johnson
 */
class SteamID
{
    // RAW Steam ID value as a string. (a plain number.)
    public $value;

    // Array of converted values. Indexed by FORMAT_xxx
    // this is a cache of formatted values, filled in
    // by Format or Parse.
    public $formatted;

    const FORMAT_AUTO = 0;     // Auto-detect format --- this also supports
                                // other unlisted formats such as
                                // full profile URLs.
    const FORMAT_STEAMID32 = 1; // Classic STEAM_x:y:zzzzzz | x = 0/1
    const FORMAT_STEAMID64 = 2; // SteamID64: 7656119xxxxxxxxxx
    const FORMAT_STEAMID3 = 3; // SteamID3 format: [U:1:xxxxxx]
    const FORMAT_S32 = 4; // Raw 32-bit SIGNED format.
                                // this is a raw steamid index that overflows
                                // into negative bitspace.
                                // This is the format that SourceMod returns
                                // with GetSteamAccountID, and will always
                                // fit into a 32-bit signed variable. (e.g.
                                // a 32-bit PHP integer).
    const FORMAT_RAW = 5; // Raw index. like 64-bit minus the base value.
    const FORMAT_VANITY = 6; // Vanity URL name. Forward conversion only.

    const STEAMID64_BASE = '76561197960265728';

    // max allowed value. (sanity check)
    // 2^36; update this in approx 2,400,000 years
    const MAX_VALUE = '68719476736';

    private static $steam_api_key = false;
    private static $default_detect_raw = false;
    private static $default_resolve_vanity = false;

    /** -----------------------------------------------------------------------
     * Set an API key to use for resolving Custom URLs. If this isn't set
     * custom URL resolution will be done by parsing the profile XML.
     *
     * @param string $key API Key
     *
     * @see http://steamcommunity.com/dev/apikey
     */
    public static function SetSteamAPIKey($key)
    {
        if (empty($key)) {
            self::$steam_api_key = false;
        }
        self::$steam_api_key = $key;
    }

    /** -----------------------------------------------------------------------
     * Set the default setting for $detect_raw for Parse().
     *
     * @param bool $parseraw Default $detect_raw value, see Parse function.
     */
    public static function SetParseRawDefault($parseraw)
    {
        self::$default_detect_raw = $parseraw;
    }

    /** -----------------------------------------------------------------------
     * Set the default setting for $resolve_vanity for Parse().
     *
     * @param bool $resolve_vanity Default $resolve_vanity value,
     *                             see Parse function.
     */
    public static function SetResolveVanityDefault($resolve_vanity)
    {
        self::$default_resolve_vanity = $resolve_vanity;
    }

    /** -----------------------------------------------------------------------
     * Construct an instance.
     *
     * @param string $raw Raw value of Steam ID.
     */
    private function __construct($raw)
    {
        $this->value = $raw;
        $this->formatted[self::FORMAT_RAW] = $raw;
    }

    /** -----------------------------------------------------------------------
     * Make a cURL request and return the contents.
     *
     * @param string $url URL to request.
     *
     * @return string|false Contents of result or FALSE if the request failed.
     */
    private static function Curl($url)
    {
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
        curl_setopt($ch, CURLOPT_FOLLOWLOCATION, 1);

        $data = curl_exec($ch);
        curl_close($ch);

        return $data;
    }

    /** -----------------------------------------------------------------------
     * Parse a Steam ID.
     *
     * @param string $input          Input to parse.
     * @param int    $format         Input formatting, see FORMAT_ constants.
     *                               Defaults to FORMAT_AUTO which detects the format.
     * @param bool   $resolve_vanity Detect and resolve vanity URLs. (only used
     *                               with FORMAT_AUTO. Default option set with
     *                               SetResolveVanityDefault.
     * @param bool   $detect_raw     Detect and parse RAW values. (only used with
     *                               FORMAT_AUTO. e.g "123" will resolve to the
     *                               SteamID with the raw value 123, and not a
     *                               vanity-url named "123". Default option set with
     *                               SetParseRawDefault.
     *
     * @return SteamID|false SteamID instance or FALSE if the input is invalid
     *                       or unsupported.
     */
    public static function Parse($input,
                                    $format = self::FORMAT_AUTO,
                                    $resolve_vanity = null,
                                    $detect_raw = null)
    {
        if ($detect_raw === null) {
            $detect_raw = self::$default_detect_raw;
        }
        if ($resolve_vanity === null) {
            $resolve_vanity = self::$default_resolve_vanity;
        }

        switch ($format) {

            case self::FORMAT_STEAMID32:

                // validate STEAM_0/1:y:zzzzzz
                if (!preg_match(
                        '/^STEAM_[0-1]:([0-1]):([0-9]+)$/',
                        $input, $matches)) {
                    return false;
                }

                // convert to raw.
                $a = bcmul($matches[2], '2', 0);
                $a = bcadd($a, $matches[1], 0);

                $result = new self($a);
                $result->formatted[self::FORMAT_STEAMID32] = $input;

                return $result;

            case self::FORMAT_STEAMID64:

                // allow digits only
                if (!preg_match('/^[0-9]+$/', $input)) {
                    return false;
                }

                // convert to raw (subtract base)
                $a = bcsub($input, self::STEAMID64_BASE, 0);

                // sanity range check.
                if (bccomp($a, '0', 0) < 0) {
                    return false;
                }
                if (bccomp($a, self::MAX_VALUE, 0) > 0) {
                    return false;
                }

                $result = new self($a);
                $result->formatted[self::FORMAT_STEAMID64] = $input;

                return $result;

            case self::FORMAT_STEAMID3:

                // validate [U:1:xxxxxx]
                if (!preg_match('/^\[U:1:([0-9]+)\]$/', $input, $matches)) {
                    return false;
                }

                $a = $matches[1];

                // sanity range check.
                if (bccomp($a, self::MAX_VALUE, 0) > 0) {
                    return false;
                }
                $result = new self($a);
                $result->formatted[self::FORMAT_STEAMID3] = $input;

                return $result;

            case self::FORMAT_S32:

                // validate signed 32-bit format
                if (!preg_match('/^(-?[0-9]+)$/', $input)) {
                    return false;
                }

                $a = $input;

                // 32-bit range check
                if (bccomp($a, '2147483647', 0) > 0) {
                    return false;
                }
                if (bccomp($a, '-2147483648', 0) < 0) {
                    return false;
                }
                if (bccomp($a, '0', 0) < 0) {
                    $a = bcadd($a, '4294967296', 0);
                }
                $result = new self($a);
                $result->formatted[self::FORMAT_S32] = $input;

                return $result;

            case self::FORMAT_RAW:

                // validate digits only
                if (!preg_match('/^[0-9]+$/', $input)) {
                    return false;
                }

                // sanity range check
                if (bccomp($input, self::MAX_VALUE, 0) > 0) {
                    return false;
                }

                return new self($input);

            case self::FORMAT_VANITY:

                // validate characters.
                if (!preg_match('/^[a-zA-Z0-9_-]{2,}$/', $input)) {
                    return false;
                }

                $result = self::ConvertVanityURL($input);
                if ($result !== false) {
                    $result->formatted[self::FORMAT_VANITY] = $input;

                    return $result;
                }
        }

        // Auto detect format:

        $input = trim($input);
        $result = self::Parse($input, self::FORMAT_STEAMID32);
        if ($result !== false) {
            return $result;
        }
        $result = self::Parse($input, self::FORMAT_STEAMID64);
        if ($result !== false) {
            return $result;
        }
        $result = self::Parse($input, self::FORMAT_STEAMID3);
        if ($result !== false) {
            return $result;
        }

        if (preg_match(
                '/^(?:https?:\/\/)?(?:www.)?steamcommunity.com\/profiles\/([0-9]+)\/*$/',
                $input, $matches)) {
            $result = self::Parse($matches[1], self::FORMAT_STEAMID64);
            if ($result !== false) {
                return $result;
            }
        }

        if ($resolve_vanity) {

            // try the name directly
            $result = self::Parse($input, self::FORMAT_VANITY);
            if ($result !== false) {
                return $result;
            }

            // try a full URL.
            if (preg_match(
                    '/^(?:https?:\/\/)?(?:www.)?steamcommunity.com\/id\/([a-zA-Z0-9_-]{2,})\/*$/',
                    $input, $matches)) {
                $result = self::ConvertVanityURL($matches[1]);
                if ($result !== false) {
                    return $result;
                }
            }
        }

        if ($detect_raw) {
            $result = self::Parse($input, self::FORMAT_S32);
            if ($result !== false) {
                return $result;
            }
            $result = self::Parse($input, self::FORMAT_RAW);
            if ($result !== false) {
                return $result;
            }
        }

        // unknown stem
        return false;
    }

    /** -----------------------------------------------------------------------
     * Convert a vanity URL into a SteamID instance.
     *
     * @param string $vanity_url_name The text part of the person's vanity URL.
     *                                e.g http://steamcommunity.com/id/gabelogannewell
     *                                would use "gabelogannewell"
     *
     * @return SteamID|false SteamID instance or FALSE on failure.
     */
    public static function ConvertVanityURL($vanity_url_name)
    {
        if (empty($vanity_url_name)) {
            return false;
        }

        if (self::$steam_api_key !== false) {
            $response = self::Curl(
                'http://api.steampowered.com/ISteamUser/ResolveVanityURL/v0001/?key='
                .self::$steam_api_key
                ."&vanityurl=$vanity_url_name");
            if ($response === false) {
                throw new SteamIDResolutionException(
                        SteamIDResolutionException::CURL_FAILURE,
                        'CURL Request Failed.');
            }

            if ($response == '') {
                throw new SteamIDResolutionException(
                        SteamIDResolutionException::VANITYURL_FAILED,
                        'Steam failure.');
            }

            $response = json_decode($response);
            if ($response === false) {
                throw new SteamIDResolutionException(
                        SteamIDResolutionException::VANITYURL_FAILED,
                        'Steam failure.');
            }

            $response = $response->response;

            if ($response->success == 42) {
                throw new SteamIDResolutionException(
                        SteamIDResolutionException::VANITYURL_NOTFOUND,
                        'Vanity URL doesn\'t exist.');
            }

            if ($response->success != 1) {
                throw new SteamIDResolutionException(
                        SteamIDResolutionException::VANITYURL_FAILED,
                        'Steam failure.');
            }

            $steamid = $response->steamid;
        } else {
            // fallback to xml parsing method.

            $result = self::Curl("http://steamcommunity.com/id/$vanity_url_name?xml=1");
            if ($result === false) {
                throw new SteamIDResolutionException(
                        SteamIDResolutionException::CURL_FAILURE,
                        'CURL Request Failed.');
            }

            $parser = xml_parser_create('');
            $values = [];
            $indexes = [];
            xml_parse_into_struct($parser, $result, $values, $indexes);
            xml_parser_free($parser);
            if (!isset($indexes['STEAMID64']) || is_null($indexes['STEAMID64'])) {
                if (isset($indexes['ERROR']) &&
                    trim($values[$indexes['ERROR'][0]]['value']) ==
                        'The specified profile could not be found.') {
                    throw new SteamIDResolutionException(
                        SteamIDResolutionException::VANITYURL_NOTFOUND,
                        'Vanity URL doesn\'t exist.');
                }

                throw new SteamIDResolutionException(
                        SteamIDResolutionException::VANITYURL_FAILED,
                        'Invalid Vanity URL or Steam failure.');
            }
            $steamid = $indexes['STEAMID64'];
            $steamid = $values[$steamid[0]]['value'];
        }

        return self::Parse($steamid, self::FORMAT_STEAMID64);
    }

    /** -----------------------------------------------------------------------
     * Format this SteamID to a string.
     *
     * @param int $format Output format. See FORMAT_xxx constants.
     *
     * @return string|false Formatted Steam ID. FALSE if an invalid format is
     *                      given or the desired format cannot contain the
     *                      SteamID.
     */
    public function Format($format)
    {
        if (isset($this->formatted[$format])) {
            return $this->formatted[$format];
        }

        switch ($format) {
            case self::FORMAT_STEAMID32:
                $z = bcdiv($this->value, '2', 0);
                $y = bcmul($z, '2', 0);
                $y = bcsub($this->value, $y, 0);
                $formatted = "STEAM_1:$y:$z";
                $this->formatted[$format] = $formatted;

                return $formatted;

            case self::FORMAT_STEAMID64:
                $formatted = bcadd($this->value, self::STEAMID64_BASE, 0);
                $this->formatted[$format] = $formatted;

                return $formatted;

            case self::FORMAT_STEAMID3:
                $formatted = "[U:1:$this->value]";
                $this->formatted[$format] = $formatted;

                return $formatted;

            case self::FORMAT_S32:
                if (bccomp($this->value, '4294967296', 0) >= 0) {
                    return false; // too large for s32.
                }

                if (bccomp($this->value, '2147483648', 0) >= 0) {
                    $formatted = bcsub($this->value, '4294967296', 0);
                } else {
                    $formatted = $this->value;
                }
                $this->formatted[$format] = $formatted;

                return $formatted;

            // (raw is always cached)
        }

        return false;
    }
}
